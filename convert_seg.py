import multiprocessing
import shutil
from multiprocessing import Pool

import SimpleITK as sitk
import numpy as np
from batchgenerators.utilities.file_and_folder_operations import *
from nnunetv2.dataset_conversion.generate_dataset_json import generate_dataset_json
from nnunetv2.paths import nnUNet_raw

def copy_BraTS_segmentation_and_convert_labels_to_nnUNet(in_file: str, out_file: str) -> None:
    # use this for segmentation only!!!
    # nnUNet wants the labels to be continuous. BraTS is 0, 1, 2, 4 -> we make that into 0, 1, 2, 3
    img = sitk.ReadImage(in_file)
    img_npy = sitk.GetArrayFromImage(img)

    uniques = np.unique(img_npy)
    for u in uniques:
        if u not in [0, 1, 2, 4]:
            raise RuntimeError('unexpected label')

    seg_new = np.zeros_like(img_npy)
    seg_new[img_npy == 4] = 3
    seg_new[img_npy == 2] = 1
    seg_new[img_npy == 1] = 2
    img_corr = sitk.GetImageFromArray(seg_new)
    img_corr.CopyInformation(img)
    sitk.WriteImage(img_corr, out_file)


if __name__ == '__main__':
    brats_data_dir = '/projects/BraTS/BraTS/BraTS2021_Training_Data/'
    task_id = 1
    foldername = "Dataset%03.0d" % (task_id)

    # setting up nnU-Net folders
    out_base = join(nnUNet_raw, foldername)
    labelstr = join(out_base, "labelsTr")
    maybe_mkdir_p(labelstr)

    case_ids = subdirs(brats_data_dir, prefix='BraTS', join=False)

    for c in case_ids:
        print(f'Converting {join(brats_data_dir, c, c + "_seg.nii.gz")} to {join(labelstr, c + ".nii.gz")}')
        copy_BraTS_segmentation_and_convert_labels_to_nnUNet(join(brats_data_dir, c, c + '_seg.nii.gz'),
                                                             join(labelstr, c + '.nii.gz'))
