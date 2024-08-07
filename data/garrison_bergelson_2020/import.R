# Import script for peekbank
# Garrison et al. (2020), Infancy raw data
# https://doi.org/10.1111/infa.12333
# Mike Frank 12/8/202

library(tidyverse)
library(here)

source(here("helper_functions", "common.R"))
dataset_name <- "garrison_bergelson_2020"
data_path <- init(dataset_name)

# yoursmy_test.Rds: binned data with subject excludes implemented, output at end of dataprep/yoursmy_dataprep_eyetracking.Rmd

d_low <- readRDS(here(data_path, "eyetracking/yoursmy_test_taglowdata.Rds"))

################## TABLE SETUP ##################

### 1. DATASET TABLE
dataset <- tibble(
  dataset_id = 0,
  lab_dataset_id = "yoursmy",
  dataset_name = "garrison_bergelson_2020",
  shortcite = "Garrison et al. (2020)",
  cite = "Garrison, H., Baudet, G., Breitfeld, E., Aberman, A., & Bergelson, E. (2020). Familiarity plays a small role in noun comprehension at 12-18 months. Infancy, 25, 458-477.",
  dataset_aux_data = NA
)

### 2. SUBJECTS TABLE
demographics <- read_csv(here(data_path, "yoursmy_ages.csv")) %>%
  left_join(read_csv(here(data_path, "yoursmy_demo_public.csv")) %>%
    rename(SubjectNumber = Name) %>%
    mutate(SubjectNumber = str_to_lower(SubjectNumber)))

raw_cdi_data <- read_csv(here(data_path, "yoursmy_CDI_data_b_clean.csv"))

cdi_data <- raw_cdi_data %>%
  mutate(
    lab_subject_id = paste0("y", str_pad(subject_id, 2, pad = "0")),
    comp = as.numeric(`Words Understood`),
  ) %>%
  mutate(subject_aux_data = pmap(
    list(`Words Understood`, `Words Produced`, age),
    function(comp, prod, age) {
      toJSON(list(cdi_responses = list(
        list(rawscore = unbox(comp), age = unbox(age), measure = unbox("comp"), language = unbox("English (American)"), instrument_type = unbox("wg")),
        list(rawscore = unbox(prod), age = unbox(age), measure = unbox("prod"), language = unbox("English (American)"), instrument_type = unbox("wg"))
      )))
    }
  )) %>%
  select(lab_subject_id, subject_aux_data)


subjects <- demographics %>%
  select(SubjectNumber, Sex) %>%
  mutate(
    subject_id = 0:(n() - 1),
    native_language = "eng",
    Sex = ifelse(Sex == "M", "male", "female")
  ) %>%
  rename(
    lab_subject_id = SubjectNumber,
    sex = Sex
  ) %>%
  left_join(cdi_data) %>%
  mutate(subject_aux_data = as.character(subject_aux_data))

### 3. STIMULI TABLE
stimuli <- d_low %>%
  select(TargetImage, DistractorImage) %>%
  pivot_longer(cols = c(TargetImage, DistractorImage), names_to = "type", values_to = "image") %>% 
  distinct() %>%
  mutate(
    # an earlier version used the audio name here,
    # but since the audio and the image names match, we can simplify
    original_stimulus_label = str_replace(
      str_replace(
        image,
        "[^A-Za-z]+", ""
      ),
      ".jpg", ""
    ),
    english_stimulus_label = original_stimulus_label,
    stimulus_novelty = "familiar",
    lab_stimulus_id = image,
    stimulus_image_path = image,
    image_description = original_stimulus_label,
    image_description_source = "image path",
    dataset_id = 0
  ) %>%
  ungroup() %>%
  select(
    original_stimulus_label, english_stimulus_label, stimulus_novelty,
    stimulus_image_path, lab_stimulus_id, dataset_id, image_description, image_description_source
  ) %>%
  distinct() %>%
  mutate(
    stimulus_id = 0:(n() - 1),
    stimulus_aux_data = NA
  )

### 4. ADMINISTRATIONS TABLE

administrations <- demographics %>%
  mutate(
    administration_id = 0:(n() - 1),
    subject_id = 0:(n() - 1),
    dataset_id = 0,
    age = Age_Mo,
    lab_age = Age_Mo,
    lab_age_units = "months",
    monitor_size_x = 1280,
    monitor_size_y = 1024,
    sample_rate = 500,
    tracker = "Eyelink 1000+",
    coding_method = "eyetracking",
    administration_aux_data = NA
  ) %>%
  select(
    administration_id, dataset_id, subject_id, age, lab_age, lab_age_units,
    monitor_size_x, monitor_size_y, sample_rate, tracker, coding_method, administration_aux_data
  )

### 4.5 TRIAL TABLE PREP
trial_table <- d_low %>%
  select(
    AudioTarget,
    condition = TrialType,
    target_side = TargetSide,
    target_image_full = TargetImage,
    distractor_image_full = DistractorImage,
    point_of_disambiguation = TargetOnset,
    trial_order = Trial,
    lab_subject_id = SubjectNumber
  ) %>%
  distinct() %>%
  ungroup() %>%
  separate(AudioTarget,
    into = c("full_phrase", "original_stimulus_label"),
    sep = "[_\\.]"
  ) %>%
  mutate(
    full_phrase = case_when(
      full_phrase == "can" ~ "Can you find the",
      full_phrase == "do" ~ "Do you see the",
      full_phrase == "look" ~ "Look at the",
      full_phrase == "where" ~ "Where is the"
    ),
    target_image = str_replace(target_image_full, "[0-9]*\\.jpg", ""),
    distractor_image = str_replace(distractor_image_full, "[0-9]*\\.jpg", ""),
  ) %>%
  group_by(target_image, target_side, distractor_image, condition, point_of_disambiguation) %>%
  mutate(trial_type_id = cur_group_id() - 1) %>%
  ungroup()

### 5. TRIAL TYPES TABLE
trial_types <- trial_table %>%
  mutate(target_side = ifelse(target_side == "L", "left", "right")) %>%
  left_join(stimuli %>% # join in target IDs
    select(stimulus_id, lab_stimulus_id) %>%
    rename(target_image_full = lab_stimulus_id)) %>%
  rename(target_id = stimulus_id) %>%
  left_join(stimuli %>% # join in distractor IDs
    select(stimulus_id, lab_stimulus_id) %>%
    rename(distractor_image_full = lab_stimulus_id)) %>%
  rename(distractor_id = stimulus_id) |>
  select(
    trial_type_id, full_phrase, point_of_disambiguation,
    target_side, condition, distractor_id, target_id
  ) %>%
  mutate(
    lab_trial_id = NA,
    full_phrase_language = "eng",
    aoi_region_set_id = 0,
    dataset_id = 0,
    vanilla_trial = TRUE,
    trial_type_aux_data = NA
  )

### 6. TRIALS TABLE
trials <- trial_table %>%
  distinct(trial_order, trial_type_id, lab_subject_id) %>%
  mutate(
    trial_id = 0:(n() - 1),
    trial_aux_data = NA,
    excluded = FALSE,
    exclusion_reason = NA
  ) %>%
  select(-lab_subject_id)

### 7. AOI REGION SETS TABLE
# recall screen is 1280 x 1024
# we could probably logic this out, we get these as locations: (320, 512) (960, 512)
# but I am putting NA because we actually already have the AOIs provided
aoi_region_sets <- tibble(
  aoi_region_set_id = 0,
  l_x_max = NA,
  l_x_min = NA,
  l_y_max = NA,
  l_y_min = NA,
  r_x_max = NA,
  r_x_min = NA,
  r_y_max = NA,
  r_y_min = NA
)

### 8. XY TABLE
timepoints <- d_low %>%
  rename(
    x = CURRENT_FIX_X,
    y = CURRENT_FIX_Y,
    aoi = gaze,
    t = Time,
    lab_subject_id = SubjectNumber,
    trial_order = Trial
  ) %>%
  left_join(trial_table) %>%
  left_join(trials) %>%
  left_join(subjects) %>%
  left_join(administrations) %>%
  mutate(point_of_disambiguation = TargetOnset)

xy_timepoints <- timepoints %>%
  select(x, y, t, point_of_disambiguation, administration_id, trial_id) %>%
  # not using the rezeroing function because times are already relative to trial onset
  rename(t_zeroed = t) %>%
  peekds::normalize_times() %>%
  peekds::resample_times(table_type = "xy_timepoints")

### 9. AOI TIMEPOINTS TABLE
aoi_timepoints <- timepoints %>%
  select(aoi, t, point_of_disambiguation, administration_id, trial_id) %>%
  mutate(aoi = str_to_lower(ifelse(is.na(aoi), "missing", as.character(aoi)))) %>%
  # not using the rezeroing function because times are already relative to trial onset
  rename(t_zeroed = t) %>%
  peekds::normalize_times() %>%
  peekds::resample_times(table_type = "aoi_timepoints")



################## ENTERTAINING PLOT ##################
aoi_timepoints %>%
  left_join(trials) %>%
  left_join(trial_types) %>%
  group_by(t_norm, condition) %>%
  filter(aoi %in% c("target", "distractor")) %>%
  summarise(correct = mean(aoi == "target")) %>%
  ggplot(aes(x = t_norm, y = correct, col = condition)) +
  geom_line() +
  xlim(-3000, 4000) +
  ylim(.4, .75) +
  geom_hline(aes(yintercept = .5), lty = 2) +
  theme_bw()

write_and_validate(
  dataset_name = dataset_name,
  cdi_expected = TRUE,
  dataset,
  subjects,
  stimuli,
  administrations,
  trial_types,
  trials,
  aoi_region_sets,
  xy_timepoints,
  aoi_timepoints
)


table_2 <- trial_types %>% pivot_longer(
  cols = c(distractor_id, target_id),
  names_to = "stimulus_type",
  values_to = "stimulus_id"
)

one_not_in_two <- table_2 %>%
  dplyr::anti_join(stimuli, by = "stimulus_id")
