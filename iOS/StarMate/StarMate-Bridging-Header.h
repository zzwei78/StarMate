//
// StarMate-Bridging-Header.h
// StarMate
//
// Bridging header for opencore-amrnb C library
//

#ifndef StarMate_Bridging_Header_h
#define StarMate_Bridging_Header_h

// opencore-amrnb encoder interface
#include "Domain/Codec/include/interf_enc.h"

// opencore-amrnb decoder interface
#include "Domain/Codec/include/interf_dec.h"

// AMR test audio data (pre-encoded 32-byte frames)
#include "Data/Services/amr_source_file.h"

#endif /* StarMate_Bridging_Header_h */
