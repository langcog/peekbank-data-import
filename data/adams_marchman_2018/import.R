# process Adams et al. (2018) data
## libraries
library(here)
library(janitor)
library(tidyverse)
library(readxl)
library(peekds)
library(osfr)

## constants
sampling_rate_hz <- 30
sampling_rate_ms <- 1000/30
dataset_name <- "adams_marchman_2018"
read_path <- here("data",dataset_name,"raw_data")
write_path <- here("data",dataset_name, "processed_data")

# processed data filenames
dataset_table_filename <- "datasets.csv"
aoi_table_filename <- "aoi_timepoints.csv"
subject_table_filename <- "subjects.csv"
administrations_table_filename <- "administrations.csv"
stimuli_table_filename <- "stimuli.csv"
trial_types_table_filename <- "trial_types.csv"
trials_table_filename <- "trials.csv"
aoi_regions_table_filename <-  "aoi_region_sets.csv"
xy_table_filename <-  "xy_timepoints.csv"
#osf_token <- read_lines(here("osf_token.txt"))


remove_repeat_headers <- function(d, idx_var) {
  d[d[,idx_var] != idx_var,]
}


# download datata from osf
#peekds::get_raw_data(dataset_name, path = read_path)


# read raw icoder files
#16-month-olds
d_raw_16 <- read_delim(fs::path(read_path, "TL316AB.ichart.n69.txt"),
                    delim = "\t") %>%
  mutate(order_uniquified=Order) %>%
  relocate(order_uniquified, .after = `Order`) %>%
  mutate(row_number = as.numeric(row.names(.))) %>%
  relocate(row_number, .after = `Sub Num`)
# no modifications to Order needed in this dataset, because all participants received two distinct orders
# this column is needed to disambiguate administrations for one subject who received the same order twice 
# in the 18-month-old group below

#18-month-olds
d_raw_18 <- read_delim(fs::path(read_path, "TL318AB.ichart.n67.txt"),
                       delim = "\t") %>%
  #one participant (Sub Num 12959) was administered the same order twice 
  #this leads to problems down the road with determining administration id and resampling times
  # to avoid this, we need to handle the second presentation of the same order as a separate "order" 
  #(in order to capture that it is a distinct administration)
  #strategy: add row numbers as a new column to disambiguate otherwise identical trial information
  mutate(row_number = as.numeric(row.names(.))) %>%
  relocate(row_number, .after = `Sub Num`) %>%
  group_by(`Sub Num`,Order, `Tr Num`) %>%
  mutate(
    order_uniquified = case_when(
      `Sub Num`=="12959" ~ ifelse(row_number<max(row_number),"TL2-2-1","TL2-2-2"),
      TRUE ~ Order
    )) %>%
  relocate(order_uniquified, .after = `Order`) %>%
  ungroup()
  
#combine
d_raw <- bind_rows(d_raw_16,d_raw_18)


# remove any column with all NAs (these are columns
# where there were variable names but no eye tracking data)
d_filtered <- d_raw %>%
  select_if(~sum(!is.na(.)) > 0) %>%
  filter(!is.na(`Sub Num`)) # remove some residual NA rows

# Create clean column headers --------------------------------------------------
d_processed <-  d_filtered %>%
  remove_repeat_headers(idx_var = "Months") %>%
  clean_names()

# Relabel time bins --------------------------------------------------
old_names <- colnames(d_processed)
metadata_names <- old_names[!str_detect(old_names,"x\\d|f\\d")]
pre_dis_names <- old_names[str_detect(old_names, "x\\d")]
post_dis_names  <- old_names[str_detect(old_names, "f\\d")]

pre_dis_names_clean <- round(seq(from = length(pre_dis_names) * sampling_rate_ms,
                           to = sampling_rate_ms,
                           by = -sampling_rate_ms) * -1,0)

post_dis_names_clean <-  post_dis_names %>% str_remove("f")

colnames(d_processed) <- c(metadata_names, pre_dis_names_clean, post_dis_names_clean)

### truncate columns at F3833, since trials are almost never coded later than this timepoint
## TO DO: check in about this decision
post_dis_names_clean_cols_to_remove <- post_dis_names_clean[117:length(post_dis_names_clean)]
#remove
d_processed <- d_processed %>%
  select(-all_of(post_dis_names_clean_cols_to_remove))

#create trial_order variable as tr_num variable
d_processed <- d_processed  %>%
  mutate(trial_order=as.numeric(as.character(tr_num))) 

#add overall row number (collapsing across 16- and 18-month-old data) to track unique instances
d_processed <- d_processed %>%
  mutate(overall_row_number = as.numeric(row.names(.))) %>%
  relocate(overall_row_number, .after = `sub_num`)

# Convert to long format --------------------------------------------------
d_tidy <- d_processed %>%
  pivot_longer(names_to = "t", cols = `-600`:`3833`, values_to = "aoi")

# recode 0, 1, ., - as distracter, target, other, NA [check in about this]
# this leaves NA as NA
d_tidy <- d_tidy %>%
  rename(aoi_old = aoi) %>%
  mutate(aoi = case_when(
    aoi_old == "0" ~ "distractor",
    aoi_old == "1" ~ "target",
    aoi_old == "0.5" ~ "other",
    aoi_old == "." ~ "missing",
    aoi_old == "-" ~ "missing",
    is.na(aoi_old) ~ "missing"
  )) %>%
  mutate(t = as.numeric(t)) # ensure time is an integer/ numeric

# Clean up column names and add stimulus information based on existing columnns  ----------------------------------------

d_tidy <- d_tidy %>%
  filter(!is.na(sub_num)) %>%
  select(-c_image,-response,-condition, -first_shift_gap,-rt) %>%
  #left-right is from the coder's perspective - flip to participant's perspective
  mutate(target_side = factor(target_side, levels = c('l','r'), labels = c('right','left'))) %>%
  rename(left_image = r_image, right_image=l_image) %>%
  mutate(target_label = target_image) %>%
  rename(target_image_old = target_image) %>% # since target image doesn't seem to be the specific image identifier
  mutate(target_image = case_when(target_side == "right" ~ right_image,
                                      TRUE ~ left_image)) %>%
  mutate(distractor_image = case_when(target_side == "right" ~ left_image,
                                      TRUE ~ right_image))

# add exclusion information
d_tidy <- d_tidy %>%
  mutate(excluded = case_when(
    is.na(prescreen_notes) ~ FALSE,
    TRUE ~ TRUE
  )) %>%
  rename(exclusion_reason = prescreen_notes)

#create stimulus table
stimulus_table <- d_tidy %>%
  distinct(target_image,target_label) %>%
  filter(!is.na(target_image)) %>%
  mutate(dataset_id = 0,
         stimulus_novelty = "familiar",
         original_stimulus_label = target_label,
         english_stimulus_label = target_label,
         stimulus_image_path = paste0(target_image, ".pct"), # TO DO - update once images are shared/ image file path known
         image_description = target_label,
         image_description_source = "image path",
         lab_stimulus_id = target_image
  ) %>%
  mutate(stimulus_id = seq(0, length(.$lab_stimulus_id) - 1))

## add target_id  and distractor_id to d_tidy by re-joining with stimulus table on distactor image
d_tidy <- d_tidy %>%
  left_join(stimulus_table %>% select(lab_stimulus_id, stimulus_id), by=c('target_image' = 'lab_stimulus_id')) %>%
  mutate(target_id = stimulus_id) %>%
  select(-stimulus_id) %>%
  left_join(stimulus_table %>% select(lab_stimulus_id, stimulus_id), by=c('distractor_image' = 'lab_stimulus_id')) %>%
  mutate(distractor_id = stimulus_id) %>%
  select(-stimulus_id)

# get zero-indexed subject ids 
d_subject_ids <- d_tidy %>%
  distinct(sub_num) %>%
  mutate(subject_id = seq(0, length(.$sub_num) - 1))
#join
d_tidy <- d_tidy %>%
  left_join(d_subject_ids, by = "sub_num")

#get zero-indexed administration ids
d_administration_ids <- d_tidy %>%
  distinct(subject_id, sub_num, months, order_uniquified) %>%
  arrange(subject_id, sub_num, months, order_uniquified) %>%
  mutate(administration_id = seq(0, length(.$order_uniquified) - 1)) 

# create zero-indexed ids for trial_types
d_trial_type_ids <- d_tidy %>%
  #order just flips the target side, so redundant with the combination of target_id, distractor_id, target_side
  #potentially make distinct based on condition if that is relevant to the study design (no condition manipulation here)
  distinct(trial_order, target_id, distractor_id, target_side) %>%
  mutate(full_phrase = NA) %>% #unknown
  mutate(trial_type_id = seq(0, length(trial_order) - 1)) 

# joins
d_tidy_semifinal <- d_tidy %>%
  left_join(d_administration_ids) %>%
  left_join(d_trial_type_ids) 

#get zero-indexed trial ids for the trials table
d_trial_ids <- d_tidy_semifinal %>%
  distinct(overall_row_number,sub_num,order_uniquified,trial_order,trial_type_id) %>%
  mutate(trial_id = seq(0, length(.$trial_type_id) - 1)) 

#join
d_tidy_semifinal <- d_tidy_semifinal %>%
  left_join(d_trial_ids)

# add some more variables to match schema
d_tidy_final <- d_tidy_semifinal %>%
  mutate(dataset_id = 0, # dataset id is always zero indexed since there's only one dataset
         lab_trial_id = paste(order, tr_num, sep = "-"),
         aoi_region_set_id = NA, # not applicable
         monitor_size_x = NA, #unknown TO DO
         monitor_size_y = NA, #unknown TO DO
         lab_age_units = "months",
         age = as.numeric(months), # months 
         point_of_disambiguation = 0, #data is re-centered to zero based on critonset in datawiz
         tracker = "video_camera",
         sample_rate = sampling_rate_hz) %>% 
  rename(lab_subject_id = sub_num,
         lab_age = months
         )

##### AOI TABLE ####
d_tidy_final %>%
  rename(t_norm = t) %>% # original data centered at point of disambiguation
  select(t_norm, aoi, trial_id, administration_id,lab_subject_id) %>%
  #resample timepoints
  resample_times(table_type="aoi_timepoints") %>%
  mutate(aoi_timepoint_id = seq(0, nrow(.) - 1)) %>%
  write_csv(fs::path(write_path, aoi_table_filename))

##### SUBJECTS TABLE ####
d_tidy_final %>%
  distinct(subject_id, lab_subject_id,sex) %>%
  filter(!(lab_subject_id == "12608"&sex=="M")) %>% #one participant has different entries for sex - 12608 is female via V Marchman
  mutate(
    sex = factor(sex, levels = c('M','F'), labels = c('male','female')),
    native_language="eng",
    subject_aux_data = NA) %>%
  write_csv(fs::path(write_path, subject_table_filename))

##### ADMINISTRATIONS TABLE ####
d_tidy_final %>%
  distinct(administration_id,
           dataset_id,
           subject_id,
           age,
           lab_age,
           lab_age_units,
           monitor_size_x,
           monitor_size_y,
           sample_rate,
           tracker) %>%
  mutate(coding_method = "manual gaze coding",
         administration_aux_data = NA) %>%
  write_csv(fs::path(write_path, administrations_table_filename))

##### STIMULUS TABLE ####
stimulus_table %>%
  select(-target_label, -target_image) %>%
  mutate(stimulus_aux_data=NA) %>%
  write_csv(fs::path(write_path, stimuli_table_filename))

#### TRIALS TABLE ####
trials <- d_tidy_final %>%
  distinct(trial_id,
           trial_order,
           trial_type_id,
           excluded,
           exclusion_reason) %>%
  mutate(trial_aux_data = NA) %>%
  write_csv(fs::path(write_path, trials_table_filename))

##### TRIAL TYPES TABLE ####
trial_types <- d_tidy_final %>%
  distinct(trial_type_id,
           full_phrase,
           point_of_disambiguation,
           target_side,
           lab_trial_id,
           aoi_region_set_id,
           dataset_id,
           target_id,
           distractor_id) %>%
    mutate(full_phrase_language = "eng",
           condition = "", #no condition manipulation based on current documentation
           vanilla_trial = TRUE,
           trial_type_aux_data = NA
           ) %>% #all trials are vanilla
  write_csv(fs::path(write_path, trial_types_table_filename))

##### AOI REGIONS TABLE ####
# create empty other files aoi_region_sets.csv and xy_timepoints
# don't need 
# tibble(administration_id = d_tidy_final$administration_id[1],
#       aoi_region_set_id=NA,
#        l_x_max=NA ,
#        l_x_min=NA ,
#        l_y_max=NA ,
#        l_y_min=NA ,
#        r_x_max=NA ,
#        r_x_min=NA ,
#        r_y_max=NA ,
#        r_y_min=NA ) %>%
#   write_csv(fs::path(write_path, aoi_regions_table_filename))

##### XY TIMEPOINTS TABLE ####
# d_tidy_final %>% distinct(trial_id, administration_id) %>%
#   mutate(x = NA,
#          y = NA,
#          t = NA,
#          xy_timepoint_id = 0:(n()-1)) %>%
#   write_csv(fs::path(write_path, xy_table_filename))

##### DATASETS TABLE ####
# write Dataset table
data_tab <- tibble(
  dataset_id = 0, # make zero 0 for all
  dataset_name = dataset_name,
  lab_dataset_id = dataset_name, # internal name from the lab (if known)
  cite = "Adams, K. A., Marchman, V. A., Loi, E. C., Ashland, M. D., Fernald, A., & Feldman, H. M. (2018). Caregiver talk and medical risk as predictors of language outcomes in full term and preterm toddlers. Child Development, 89(5), 1674-1690. https://doi.org/10.1111/cdev.12818",
  shortcite = "Adams et al. (2018)",
  dataset_aux_data = NA
) %>%
  write_csv(fs::path(write_path, dataset_table_filename))

# validation check ----------------------------------------------------------
validate_for_db_import(dir_csv = write_path)

## OSF INTEGRATION ###
#put_processed_data(osf_token, dataset_name, write_path, osf_address = "pr6wu")
