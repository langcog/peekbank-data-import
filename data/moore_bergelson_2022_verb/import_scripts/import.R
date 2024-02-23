# Import script for peekbank
# CITATION raw data
# DOI
# USER 
# DATE

# Note: this script was based on the generic import.R and the import.R in
# garrison_bergelson_2020

library(tidyverse)
library(here)
library(peekds) 
library(osfr)
library(rjson)
library(tools)  # for file_path_sans_ext
library(glue)

DATASET_NAME <- "moore_bergelson_2022_verb"
data_path <- glue("data/{DATASET_NAME}/raw_data")
output_path <- glue("data/{DATASET_NAME}/processed_data")


DATASET_ID <- 0  # single dataset, zero-indexed
NATIVE_LANGUAGE <- "eng"  # same for every kid
SEX_NA_VALUE <- "unspecified"

MONITOR_SIZE_X <- 1280
MONITOR_SIZE_Y <- 1024
SAMPLE_RATE <- 500
TRACKER <- "Eyelink 1000+"
CODING_METHOD <- "eyetracking"

CARRIER_PHRASES <- list(
  can = "Look! She can _",
  gonna = "She's gonna _",
  about = "She's about to _ it"
)
CARRIER_PHRASE_LANGUAGE <- "eng"
PRONUNCIATION_CONDITIONS <- list(
  CP = "correctly pronounced",
  MP = "mispronounced"
)
VERB_TYPE_CONDITIONS <- list(
  reg = "regular",
  irreg = "irregular"
)
TARGET_SIDES <- c(
  L = "left",
  R = "right"
)
SINGLE_AOI_REGION_SET_ID <- 0

################## DATASET SPECIFIC READ IN CODE ##################

fixations_binned <-
  here(data_path, "data/eyetracking/vna_test_taglowdata.Rds") %>%
  readRDS %>%
  rename(lab_subject_id = SubjectNumber,
         target_image_path = TargetImage,
         distractor_image_path = DistractorImage,
         audio_path = AudioTarget,
         target_word_onset = TargetOnset,
         target_side_label = TargetSide,
         pronunciation = TrialType,  # CP/MP for correctly pronounced/mispronounced
         verb_type = VerbType,  # (reg)ular vs. (irreg)ular
         trial_order = Trial,  # in order the trials were presented
         x = looking_X,
         y = looking_Y,
         t = Time,
         aoi = gaze)  # TARGET/DISTRACTOR

demographics <-
  read_csv(
    here(data_path, "data", "demographics", "vna_age_gender_deid.csv"),
    col_types = cols(
      name = col_character(),
      sex = col_character(),
      age_at_test = col_integer(),
      age_at_test_mo = col_double(),
      young_old = col_character(),
      race = col_character(),
      race_recode = col_character()
    )) %>%
  rename(
    age_at_test_days = age_at_test,
    lab_subject_id = name)

cdi_data <- 
  read_csv(
    here(data_path, "data", "cdi", "vna_cdi_totals_both_ages.csv"),
    col_types = cols(
      SubjectNumber = col_character(),
      age = col_integer(),
      produces = col_integer(),
      CDIcomp = col_integer()
    )
  ) %>%
  rename(
    lab_subject_id = SubjectNumber,
    eng_wg_comp_rawscore = CDIcomp,
    eng_wg_prod_rawscore = produces,
  )

excluded_participants <- read_csv(
  here(data_path, "data/eyetracking/vna_excluded_participants.csv"),
  col_types = cols(
    SubjectNumber = col_character(),
    good_trials = col_integer(),
    young_old = col_character()
  ))

################## TABLE SETUP ##################

# it's very helpful to have the schema open as you do this
# https://docs.google.com/spreadsheets/d/1Z24n9vfrAmEk6_HpoTSh58LnkmSGmNJagguRpI1jwdo/edit#gid=0

### 1. DATASET TABLE 
datasets <- tibble(dataset_id = DATASET_ID,
                   lab_dataset_id = "VNA",
                   dataset_name = DATASET_NAME,
                   name = DATASET_NAME, 
                   shortcite = "Moore & Bergelson (2022)", 
                   cite = "Moore, C., & Bergelson, E. (2022). Examining the roles of regularity and lexical class in 18–26-month-olds’ representations of how words sound. Journal of Memory and Language, 126, 104337.",
                   dataset_aux_data = NA)


### 2. SUBJECTS TABLE
# Start from the subjects with eyetracking data
subject_info <- fixations_binned %>%
  distinct(lab_subject_id) %>%
  inner_join(demographics, by = "lab_subject_id",
             relationship = 'one-to-one',
             unmatched = c('error', 'drop')) %>%
  # Sort to get predictable subject_id
  arrange(lab_subject_id) %>%
  mutate(subject_id = 0:(n() - 1),
         native_language = NATIVE_LANGUAGE,
         sex = case_when(
           sex == "M" ~ 'male',
           sex == "F" ~ 'female',
           is.na(sex) ~ SEX_NA_VALUE,
           .default = 'error'
         ),
         subject_aux_data = NA)

# Note: Sex is not NA for any subjects. It can be NA in the demographics file - for subjects which were excluded before looking at their eyetracking data. Data from those subjects are not included in this dataset, however, so sex will never be NA in the subject_info table.

subjects <- subject_info %>%
  select(subject_id, sex, native_language, lab_subject_id, subject_aux_data)


### 3. STIMULI TABLE 

# Target and distractor stimuli are treated separately because targets have a (potentially mispronounced) verb and a carrier phrase associated with them, while distractors do not. See readme.txt for more details.

target_stimuli <- fixations_binned %>%
  select(stimulus_image_path = target_image_path,
         stimulus_audio_path = audio_path) %>%
  distinct() %>%
  mutate(
    # drop the extensions: jump.mp4 -> jump, joomp_can.wav -> joomp_can
    image_name = file_path_sans_ext(stimulus_image_path),
    audio_name = file_path_sans_ext(stimulus_audio_path)
  ) %>%
  # joomp_can -> joomp, can
  separate_wider_delim(
    audio_name, names = c('word', 'carrier_phrase_label'), delim = "_", cols_remove = FALSE) %>%
  mutate(
    original_stimulus_label = word,  # joomp
    english_stimulus_label = original_stimulus_label,  # joomp
    stimulus_novelty = if_else(image_name == word, 'familiar', 'novel'),  # joomp - novel, jump would be familiar
    lab_stimulus_id = glue('{image_name}_{carrier_phrase_label}-{word}'),  # jump_can-joomp
    )

distractor_stimuli <- fixations_binned %>%
  select(stimulus_image_path = distractor_image_path) %>%
  distinct() %>%
  mutate(
    image_name = file_path_sans_ext(stimulus_image_path),
    lab_stimulus_id = glue('{image_name}_distractor'),
    stimulus_novelty = 'familiar')


stimuli <-
  bind_rows(target_stimuli, distractor_stimuli) %>%
  mutate(image_description = image_name,  # jump
    image_description_source = "image path",
    dataset_id = DATASET_ID
  ) %>%
  select(original_stimulus_label, english_stimulus_label, stimulus_novelty, image_description, image_description_source,
         stimulus_image_path, lab_stimulus_id, dataset_id) %>%
  distinct() %>%
  # Sort to get reproducible stimulus_id
  arrange(lab_stimulus_id, across(everything())) %>%
  mutate(stimulus_id = 0:(n() - 1),
         stimulus_aux_data = NA)



### 4. ADMINISTRATIONS TABLE 

administrations_aux_data <- subjects %>%
  select(subject_id, lab_subject_id) %>%
  left_join(cdi_data,
             by = "lab_subject_id",
             relationship = 'one-to-one') %>%
  mutate(
    eng_wg_comp_age = age,
    eng_wg_prod_age = age
  ) %>%
  rowwise(subject_id) %>% 
  mutate(
    administration_aux_data = toJSON(across(
      c("eng_wg_comp_rawscore", "eng_wg_comp_age",
        "eng_wg_prod_rawscore","eng_wg_prod_age")
    ))) %>%
  select(subject_id, administration_aux_data)
  

administrations <- subject_info %>%
  select(subject_id, age_at_test_days) %>%
  mutate(
    administration_id = subject_id,
    dataset_id = DATASET_ID,
    # conversion formula from the list of peekbank dataset columns at
    # https://docs.google.com/spreadsheets/d/1Z24n9vfrAmEk6_HpoTSh58LnkmSGmNJagguRpI1jwdo
    age = age_at_test_days / (365.25 / 12),
    lab_age = age_at_test_days,
    lab_age_units = "days",
    monitor_size_x = MONITOR_SIZE_X,
    monitor_size_y = MONITOR_SIZE_Y,
    sample_rate = SAMPLE_RATE,
    tracker = TRACKER,
    coding_method = CODING_METHOD
  ) %>%
  inner_join(administrations_aux_data, by = "subject_id",
             relationship = 'one-to-one')


### 5. TRIAL TYPES TABLE

# Target word onsets are highly variable leading to as many trial types as there are trials.* If not for that, there would be 32 trial types: 8 verbs, 2 pronunciations, 2 sides.
#
# *Note: This wasn't guaranteed: there could have been trials with the same trial type (out of 32) *and* the same target word onset. It just didn't happen that way.

lab_to_peekbank_id_map <- stimuli %>%
  select(lab_stimulus_id, stimulus_id) %>%
  deframe

trial_info <- fixations_binned %>%
  distinct(lab_subject_id, trial_order,
           pronunciation, verb_type,
           target_side_label,
           audio_path,
           target_image_path,
           distractor_image_path,
           target_word_onset,
           bad_trial) %>%
  mutate(stimulus_audio_name = file_path_sans_ext(audio_path)) %>%
  separate_wider_delim(
    stimulus_audio_name,
    names = c("target_label", "carrier_label"),
    delim = "_",
    cols_remove = FALSE) %>%
  mutate(
    carrier_phrase = CARRIER_PHRASES[carrier_label],
    full_phrase = str_replace(carrier_phrase, '_', target_label),
    target_image_name = file_path_sans_ext(target_image_path),
    distractor_image_name = file_path_sans_ext(distractor_image_path),
    lab_target_id = glue('{target_image_name}_{carrier_label}-{target_label}'),
    lab_distractor_id = glue('{distractor_image_name}_distractor'),
    lab_trial_id = glue('{lab_target_id}_{lab_distractor_id}'),
    target_id = lab_to_peekbank_id_map[lab_target_id],
    distractor_id = lab_to_peekbank_id_map[lab_distractor_id],
    vanilla_trial = pronunciation == 'CP',  # correctly pronounced
    pronunciation = PRONUNCIATION_CONDITIONS[pronunciation],
    verb_type = VERB_TYPE_CONDITIONS[verb_type],
    condition = glue('{pronunciation} x {verb_type}'),
    point_of_disambiguation = target_word_onset,
    target_side = TARGET_SIDES[target_side_label]
    )

trial_types <- trial_info %>%
  mutate(full_phrase_language = CARRIER_PHRASE_LANGUAGE,
         dataset_id = DATASET_ID) %>%
  distinct(full_phrase, full_phrase_language, point_of_disambiguation, vanilla_trial,
           target_side, lab_trial_id, condition, dataset_id,
           distractor_id, target_id) %>%
  arrange(across(everything())) %>%
  mutate(trial_type_id = 0:(n() - 1),
         aoi_region_set_id = SINGLE_AOI_REGION_SET_ID,
         trial_type_aux_data = NA) %>%
  # move trial_type_id up
  select(trial_type_id, everything())


### 6. TRIALS TABLE 

trial_keys <- c('lab_subject_id', 'trial_order')
trial_type_keys <- c('target_id', 'target_side', 'distractor_id',
                     'point_of_disambiguation')

trials_plus <- trial_info %>%
  select(all_of(trial_keys), all_of(trial_type_keys), bad_trial) %>%
  # Match to trial types to get trial_type_id
  inner_join(trial_types, by = trial_type_keys,
    relationship = 'many-to-one',
    unmatched = c('error', 'drop')) %>%
  # Add info about excluded participants and trials
  mutate(
    partipant_excluded = lab_subject_id %in% excluded_participants$SubjectNumber,
    excluded = bad_trial | partipant_excluded,
    exclusion_reason = case_when(
      bad_trial & partipant_excluded ~ "low-data/frozen & participant excluded",
      bad_trial ~ "low-data/frozen",
      partipant_excluded ~ "participant excluded",
      TRUE ~ NA_character_)) %>%
  arrange(across(all_of(trial_keys))) %>%
  mutate(
    trial_id = 0:(n() - 1),
    trial_aux_data = NA)

# Note: we save trials_plus table because it contains columns lab_subject_id and trial_order that we will later use to match fixations_binned to trials.

trials <- trials_plus %>%
  select(trial_id, trial_type_id, trial_order, trial_aux_data,
         excluded, exclusion_reason)

# Exclusion reasons:
# - low-data - Less than 1/3 of the 20 ms bins in the window from 367 to 3970 ms after the target word onset contain fixations on the screen.
#   Other bins can contain fixations off the screen, eyetracking data not classified as fixations, or no eyetracking data at all.
# - frozen - All on-screen fixations throughout the whole trial are on the same side, including the time before the video started and the time after audio ended.
# - participant excluded - Participant was excluded because there were fewer than 16 trials trials that weren't excluded for low-data or frozen reasons. This dataset doesn't include participants who were excluded for not data-based reasons.


### 7. AOI REGION SETS TABLE

# Note: The coordinates are doubles with 1 digit after the decimal point. The way AOIs were assigned, x = 640 was considered part of the left AOI and x = 640.1 - of the right. Columns in aoi_region_sets table have to be integer, however, so we can't represent these AOIs exactly. I had a choice then between setting r_x_min to 640 and 641. I chose 640.

aoi_region_sets <- tibble(aoi_region_set_id = SINGLE_AOI_REGION_SET_ID, 
                          l_x_max = 640,
                          l_x_min = 0,
                          l_y_max = 1024,
                          l_y_min = 0,
                          r_x_max = 1280,
                          r_x_min = 640,
                          r_y_max = 1024,
                          r_y_min = 0)


### 8. XY TABLE
match_many_to_exactly_one <- function(...) {
  inner_join(...,
             relationship = 'many-to-one',
             unmatched = c('error', 'drop'))
}


timepoints <- fixations_binned %>%
  mutate(aoi = case_when(
    aoi == 'TARGET' ~ 'target',
    aoi == 'DISTRACTOR' ~ 'distractor',
    is.na(aoi) ~ 'missing',
    .default = 'error'
  )) %>%
  # Get trial_id and trial_type_id
  match_many_to_exactly_one(
    trials_plus %>%
      select(all_of(trial_keys), trial_id, trial_type_id),
    by = trial_keys) %>%
  # Get point_of_disambiguation
  match_many_to_exactly_one(
    trial_types %>%
      select(trial_type_id, point_of_disambiguation),
    by = 'trial_type_id') %>%
  # Get administration_id
  match_many_to_exactly_one(
    inner_join(subjects, administrations, by = 'subject_id') %>%
      select(lab_subject_id, administration_id),
    by = 'lab_subject_id') %>%
  select(x, y, t, aoi, point_of_disambiguation, administration_id, trial_id)

timepoints_normalized <- timepoints %>%
  # following the import script in garrison_bergelson_2020, skipping rezeroing because times are already relative to trial onset.
  rename(t_zeroed = t) %>%
  peekds::normalize_times()

xy_timepoints <- timepoints_normalized %>%
  select(x, y, t_norm, administration_id, trial_id) %>%
  peekds::resample_times(table_type = "xy_timepoints")


### 9. AOI TIMEPOINTS TABLE
aoi_timepoints <- timepoints_normalized %>%
  select(aoi, t_norm, administration_id, trial_id) %>%
  peekds::resample_times(table_type = "aoi_timepoints")


################## WRITING AND VALIDATION ##################

write_csv(datasets, file = here(output_path, "datasets.csv"))
write_csv(subjects, file = here(output_path, "subjects.csv"))
write_csv(stimuli, file = here(output_path,  "stimuli.csv"))
write_csv(administrations, file = here(output_path, "administrations.csv"))
write_csv(trial_types, file = here(output_path, "trial_types.csv"))
write_csv(trials, file = here(output_path, "trials.csv"))
write_csv(aoi_region_sets, file = here(output_path, "aoi_region_sets.csv"))
write_csv(xy_timepoints, file = here(output_path, "xy_timepoints.csv"))
write_csv(aoi_timepoints, file = here(output_path, "aoi_timepoints.csv"))


# run validator
peekds::validate_for_db_import(dir_csv = here(output_path))

# OSF integration

# Upload processed data to OSF
# osf_address <- "pr6wu"
# processed_data_path <- paste0(output_path,"/")
# put_processed_data(token = NULL, dataset_name = DATASET_NAME,
#                    path = processed_data_path, osf_address = osf_address)

# Upload raw data to OSF
# Note: code copied from put_processed_data
# raw_data_path <- paste0(data_path, "/")
# path <- raw_data_path
# osfr::osf_retrieve_node(osf_address) %>%
#   osfr::osf_ls_files(n_max = Inf) %>%
#   dplyr::filter(.data$name == dataset_name) %>%
#   osfr::osf_ls_files(n_max = Inf) %>%
#   dplyr::filter(.data$name == "raw_data") %>%
#   osfr::osf_upload(path = stringr::str_c(path,
#                                          list.files(path = path,
#                                                     recursive = TRUE)),
#                    recurse = TRUE, conflicts = "overwrite", verbose = TRUE,
#                    progress = TRUE)

################## ENTERTAINING PLOT ##################
# feel free to modify
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
