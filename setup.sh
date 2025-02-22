#!/usr/bin/env bash
# vim:ft=sh:ts=4:sw=4:sts=4:et:

ensure_dir() {
    if [[ -f "$1" ]]; then
        "  ERROR: File $1 exsits, cannot make directory"
        return 1
    fi
    if [[ ! -d "$1" ]]; then
        echo "  -> making directory $1"
        mkdir -p "$1" || {
            echo "  ERROR: Cannot make direcotry $1"
            return 1
        }
    fi
    return 0
}

ensure_file() {
    if [[ -d "$1" ]]; then
        "  ERROR: Directory $1 exsits, cannot create file"
        return 1
    fi
    if [[ ! -f "$1" ]]; then
        echo "  -> creating file $1"
        touch "$1" || {
            echo "  ERROR: Cannot create file $1"
            return 1
        }
    fi
    return 0
}

setup_path() {
    echo 'Setting up path for nnUNet...'
    ensure_dir "${LOCAL_DATA}" || return 1

    export nnUNet_raw="${LOCAL_DATA}/raw"
    echo "  -> export nnUNet_raw=${nnUNet_raw}"
    export nnUNet_preprocessed="${LOCAL_DATA}/preprocessed"
    echo "  -> export nnUNet_preprocessed=${nnUNet_preprocessed}"
    export nnUNet_results="/tmp/nn_unet_results/"
    echo "  -> export nnUNet_results=${nnUNet_results}"

    ensure_dir "${nnUNet_raw}" || return 1
    ensure_dir "${nnUNet_preprocessed}" || return 1
    ensure_dir "${nnUNet_results}" || return 1
    return 0
}

slink() {
    local file="$1"
    local new_file="$2"
    if [[ -L "${new_file}" ]]; then
        echo "  -> unlinking ${new_file}"
        unlink "${new_file}" || return 1
    elif [[ -f "${new_file}" ]]; then
        echo "  -> removing ${new_file}"
        rm "${new_file}" || return 1
    elif [[ -d "${new_file}" ]]; then
        echo "  ERROR: ${new_file} exists and is a directory"
        return 1
    fi
    echo "  -> linking ${file} to ${new_file}"
    ln -s "${file}" "${new_file}"
    return 0
}

convert_dataset() {
    read -p "Convert the dataset? [Y/n] " -r
    if [[ ! $REPLY =~ ^[Yy]$ && ! -z "${REPLY}" ]]; then
        echo "  -> Skipping dataset conversion"
        return 0
    fi
    echo 'Converting dataset...'
    local imagesTr="${nnUNet_raw}/Dataset001/imagesTr"
    local labelsTr="${nnUNet_raw}/Dataset001/labelsTr"
    local dataset_json="${nnUNet_raw}/Dataset001/dataset.json"
    echo "  -> imagesTr=${imagesTr}"
    echo "  -> labelsTr=${labelsTr}"
    echo "  -> dataset_json=${dataset_json}"
    ensure_dir "${imagesTr}" || return 1
    ensure_dir "${labelsTr}" || return 1
    ensure_file "${dataset_json}" || return 1

    # Original dataset structure:
    #  BraTS2021_Training_Data/ ($TRAINING_DATA)
    #  - BraTS2021_00000/
    #    - BraTS2021_00000_flair.nii.gz
    #    - BraTS2021_00000_t1.nii.gz
    #    - BraTS2021_00000_t1ce.nii.gz
    #    - BraTS2021_00000_t2.nii.gz
    #    - BraTS2021_00000_seg.nii.gz   # ground truth
    #  - BraTS2021_00001/
    #  - BraTS2021_00002/
    #  ...

    # nnUNet dataset structure:
    #  $nnUNet_raw/Dataset001/
    #  - dataset.json
    #  - imagesTr/
    #    - BraTS2021_00000_0000.nii.gz  # 0000: flair
    #    - BraTS2021_00000_0001.nii.gz  # 0001: t1
    #    - BraTS2021_00000_0002.nii.gz  # 0002: t1ce
    #    - BraTS2021_00000_0003.nii.gz  # 0003: t2
    #    - BraTS2021_00001_0000.nii.gz
    #    - BraTS2021_00001_0001.nii.gz
    #    - BraTS2021_00001_0002.nii.gz
    #    - BraTS2021_00001_0003.nii.gz
    #    - BraTS2021_00002_0000.nii.gz
    #    - ...
    #  - labelsTr/
    #    - BraTS2021_00000.nii.gz
    #    - BraTS2021_00001.nii.gz
    #    - BraTS2021_00002.nii.gz
    #    - ...

    [[ "$(ls -A ${imagesTr})" ]] && {
        rm "${imagesTr}"/* || return 1
    }
    [[ "$(ls -A ${labelsTr})" ]] && {
        rm "${labelsTr}"/* || return 1
    }
    for img_subdir in "${TRAINING_DATA}"/*; do
        local img_name=$(basename "${img_subdir}")
        # Linking channel images to imagesTr/
        local channels=('t1' 't1ce' 't2' 'flair')
        for ((i = 0; i < ${#channels[@]}; i++)); do
            local channel="${channels[$i]}"
            local img_file="${img_subdir}/${img_name}_${channel}.nii.gz"
            local img_new_name="${img_name}_$(printf "%04d" $i).nii.gz"
            local img_new_file="${imagesTr}/${img_new_name}"
            slink "${img_file}" "${img_new_file}" || return 1
        done
    done

    # Creates example dataset.json
    echo "Making dataset.json..."
    local num_samples="$(ls ${TRAINING_DATA} | wc -l)"
    local json_str="{
    \"channel_names\": {
        \"0\": \"t1\",
        \"1\": \"t1ce\",
        \"2\": \"t2\",
        \"3\": \"flair\"
    },
    \"labels\": {
        \"background\": 0,
        \"NCR_NET\": 1,
        \"ED\": 2,
        \"ET\": 3
    },
    \"numTraining\": ${num_samples},
    \"file_ending\": \".nii.gz\"
}"
    echo "${json_str}" > "${dataset_json}"
    echo "  -> ${dataset_json}:"
    cat "${dataset_json}"
    return 0
}

convert_labels() {
    read -p "Convert the labels? [Y/n] " -r
    if [[ ! $REPLY =~ ^[Yy]$ && ! -z "${REPLY}" ]]; then
        echo "  -> Skipping label conversion"
        return 0
    fi
    echo 'Converting labels in seg images...'
    python3 convert_seg.py || return 1
    echo '  -> done!'
    return 0
}

verify() {
    read -p 'Pre-process dataset? [Y|n] ' -r
    if [[ ! "${REPLY}" =~ ^[Yy]$ && ! -z "${REPLY}" ]]; then
        return 0
    fi
    read -p 'Verify dataset integrity? [Y|n] ' -r
    if [[ ! "${REPLY}" =~ ^[Yy]$ && ! -z "${REPLY}" ]]; then
        nnUNetv2_plan_and_preprocess -d 1 || return 1
    else
        nnUNetv2_plan_and_preprocess -d 1 --verify_dataset_integrity || return 1
    fi
    return 0
}

main() {
    PROJECT_HOME="/projects/${USER}"
    SHARED_DIR="${1:-/projects/BraTS/BraTS}"
    TRAINING_DATA="${SHARED_DIR}/BraTS2021_Training_Data"
    LOCAL_DATA="${2:-${PROJECT_HOME}/local_data/nn_unet}"

    setup_path || return 1
    convert_dataset || return 1
    convert_labels || return 1
    echo "Conversion done!"
    verify || return 1
    return 0
}

main "$@"
