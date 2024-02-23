1. Reference

Moore, C., & Bergelson, E. (2022). Examining the roles of regularity and lexical class in 18–26-month-olds’ representations of how words sound. Journal of Memory and Language, 126, 104337.
https://doi.org/10.1016/j.jml.2022.104337

2. Abstract

By around 12 months, infants have well-specified phonetic representations for the nouns they understand, for instance looking less at a car upon hearing ‘cur’ than ‘car’ (Swingley and Aslin, 2002). Here we test whether such high-fidelity representations extend to irregular nouns, and regular and irregular verbs. A corpus analysis confirms the intuition that irregular verbs are far more common than irregular nouns in speech to young children. Two eyetracking experiments then test whether toddlers are sensitive to mispronunciation in regular and irregular nouns (Experiment 1) and verbs (Experiment 2). For nouns, we find a mispronunciation effect and no regularity effect in 18-month-olds. For verbs, in Experiment 2a, we find only a regularity effect and no mispronunciation effect in 18-month-olds, though toddlers’ poor comprehension overall limits interpretation. Finally, in Experiment 2b we find a mispronunciation effect and no regularity effect in 26-month-olds. The interlocking roles of lexical class and regularity for wordform representations and early word learning are discussed.

3. Original study info

This dataset currently contains data from Experiment 2a and 2b.

Key conditions. (note: column names refer to the dataframe in raw_data/data/eyetracking/vna_test_taglowdata.Rds)
- Whether the verb was regular or irregular. Column VerbType.
- Whether the verb was mispronounced. Column TrialType with values CP (for *c*orrectly pronounced) and MP (for mispronounced).
- Age group: young (15-20 months) or old (23-29) months. Column young_old. It is not getting directly imported but can be reconstructed from the age column in the administrations table.

4. Importing decisions

    # Stimuli

    When creating the stimuli table, we defined a target stimulus to be a combination of:

    - Label (verb). This includes the pronunciation. So, “jump” and “joomp” are considered to be different labels.
    - Carrier phrase. This information was redundant with the label information in this experiment.
    - Image (video) associated with the label. There is a “jump” video but there isn’t a separate “joomp” video.

    For example, label "joomp" spliced into "Look! She can ..." and the associated "jump" video constitute one target stimulus which we will label as "jump_can-joomp" in the "lab_stimulus_label" column.

    Distractors, however, don't have a label or a carrier phrase associated with them and so there isn’t an obvious target stimulus we could assign to represent them. We could have arbitrarily selected one of the two target stimuli that use the same video; for example, the one with the correctly pronounced verb. Instead, we added distractors as separate stimuli and gave them labels like “jump_distractor”.

    # Trial types

    The target word onset time varied considerably between trials. Because of that, we ended up with as many trial types as there were trials.

    # AOI region sets

    Points with x coordinate 640 were assigned to the “left” AOI, and with 640.1 and above - to the right AOI. To represent that in the table, we would need to set r_x_min to 640.1 or any other number larger than 640 and not larger than 640.1. The table columns are interger, however, so we could either go with 640 or 641. We went with 640.

5. Importing ambiguity

All issues are described in “Importing decisions” above.
