#ifndef AMR_SOURCE_FILE_H
#define AMR_SOURCE_FILE_H

#include <stdint.h>

// AMR-NB test audio data (pre-encoded, 32 bytes per frame, no header)
extern const unsigned char amr_source_file_bin[];
extern const unsigned int amr_source_file_bin_len;

// C helper functions for Swift access
const unsigned char* get_amr_test_data(void);
unsigned int get_amr_test_data_length(void);

#endif // AMR_SOURCE_FILE_H
