#include "absd.h"
#include <mach/mach.h>
#include <mach/mig.h>
#include <mach/mig_errors.h>
#include <mach/ndr.h>
#include <string.h>

#ifndef NDR_RECORD
#define NDR_RECORD NDR_record
#endif

#pragma pack(push, 4)

/* 1200: NACInit */
typedef struct {
    mach_msg_header_t Head;
    mach_msg_body_t msgh_body;
    mach_msg_ool_descriptor_t cert;
    NDR_record_t NDR;
    uint32_t magic;
    mach_msg_type_number_t certCnt;
} __Request__rawNACInit_t;

typedef struct {
    mach_msg_header_t Head;
    mach_msg_body_t msgh_body;
    mach_msg_ool_descriptor_t session_request;
    NDR_record_t NDR;
    uint64_t context;
    mach_msg_type_number_t session_requestCnt;
    mach_msg_trailer_t trailer;
} __Reply__rawNACInit_t;

/* 1201: NACKeyEstablishment */
typedef struct {
    mach_msg_header_t Head;
    mach_msg_body_t msgh_body;
    mach_msg_ool_descriptor_t session_response;
    NDR_record_t NDR;
    uint32_t magic;
    uint64_t context;
    mach_msg_type_number_t session_responseCnt;
} __Request__rawNACKeyEstablishment_t;

typedef struct {
    mach_msg_header_t Head;
    NDR_record_t NDR;
    kern_return_t RetCode;
    mach_msg_trailer_t trailer;
} __Reply__rawNACKeyEstablishment_t;

/* 1202: NACSign */
typedef struct {
    mach_msg_header_t Head;
    mach_msg_body_t msgh_body;
    mach_msg_ool_descriptor_t data;
    NDR_record_t NDR;
    uint32_t magic;
    uint64_t context;
    mach_msg_type_number_t dataCnt;
} __Request__rawNACSign_t;

typedef struct {
    mach_msg_header_t Head;
    mach_msg_body_t msgh_body;
    mach_msg_ool_descriptor_t signature;
    NDR_record_t NDR;
    mach_msg_type_number_t signatureCnt;
    mach_msg_trailer_t trailer;
} __Reply__rawNACSign_t;

#pragma pack(pop)

kern_return_t rawNACInit(
    mach_port_t server,
    uint32_t magic,
    vm_offset_t cert,
    mach_msg_type_number_t certCnt,
    uint64_t *context,
    vm_offset_t *session_request,
    mach_msg_type_number_t *session_requestCnt
) {
    union {
        __Request__rawNACInit_t In;
        __Reply__rawNACInit_t Out;
    } Mess;

    __Request__rawNACInit_t *InP = &Mess.In;
    __Reply__rawNACInit_t *OutP = &Mess.Out;

    mach_port_t reply_port = mig_get_reply_port();

    memset(InP, 0, sizeof(*InP));
    InP->Head.msgh_bits = MACH_MSGH_BITS_COMPLEX | MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, MACH_MSG_TYPE_MAKE_SEND_ONCE);
    InP->Head.msgh_remote_port = server;
    InP->Head.msgh_local_port = reply_port;
    InP->Head.msgh_id = 1200;
    InP->Head.msgh_size = sizeof(*InP);

    InP->msgh_body.msgh_descriptor_count = 1;
    InP->cert.address = (void *)cert;
    InP->cert.size = certCnt;
    InP->cert.deallocate = FALSE;
    InP->cert.copy = MACH_MSG_VIRTUAL_COPY;
    InP->cert.type = MACH_MSG_OOL_DESCRIPTOR;

    InP->NDR = NDR_RECORD;
    InP->magic = magic;
    InP->certCnt = certCnt;

    kern_return_t kr = mach_msg(&InP->Head,
                                MACH_SEND_MSG | MACH_RCV_MSG,
                                sizeof(*InP),
                                sizeof(*OutP),
                                reply_port,
                                MACH_MSG_TIMEOUT_NONE,
                                MACH_PORT_NULL);

    if (kr != MACH_MSG_SUCCESS) {
        mig_dealloc_reply_port(reply_port);
        return kr;
    }

    if (OutP->Head.msgh_id != 1300) {
        if (OutP->Head.msgh_id == MACH_NOTIFY_SEND_ONCE) {
            return MIG_SERVER_DIED;
        }
        return MIG_REPLY_MISMATCH;
    }

    if (!(OutP->Head.msgh_bits & MACH_MSGH_BITS_COMPLEX)) {
        return ((mig_reply_error_t *)OutP)->RetCode;
    }

    *context = OutP->context;
    *session_request = (vm_offset_t)OutP->session_request.address;
    *session_requestCnt = OutP->session_requestCnt;

    return KERN_SUCCESS;
}

kern_return_t rawNACKeyEstablishment(
    mach_port_t server,
    uint32_t magic,
    uint64_t context,
    vm_offset_t session_response,
    mach_msg_type_number_t session_responseCnt
) {
    union {
        __Request__rawNACKeyEstablishment_t In;
        __Reply__rawNACKeyEstablishment_t Out;
    } Mess;

    __Request__rawNACKeyEstablishment_t *InP = &Mess.In;
    __Reply__rawNACKeyEstablishment_t *OutP = &Mess.Out;

    mach_port_t reply_port = mig_get_reply_port();

    memset(InP, 0, sizeof(*InP));
    InP->Head.msgh_bits = MACH_MSGH_BITS_COMPLEX | MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, MACH_MSG_TYPE_MAKE_SEND_ONCE);
    InP->Head.msgh_remote_port = server;
    InP->Head.msgh_local_port = reply_port;
    InP->Head.msgh_id = 1201;
    InP->Head.msgh_size = sizeof(*InP);

    InP->msgh_body.msgh_descriptor_count = 1;
    InP->session_response.address = (void *)session_response;
    InP->session_response.size = session_responseCnt;
    InP->session_response.deallocate = FALSE;
    InP->session_response.copy = MACH_MSG_VIRTUAL_COPY;
    InP->session_response.type = MACH_MSG_OOL_DESCRIPTOR;

    InP->NDR = NDR_RECORD;
    InP->magic = magic;
    InP->context = context;
    InP->session_responseCnt = session_responseCnt;

    kern_return_t kr = mach_msg(&InP->Head,
                                MACH_SEND_MSG | MACH_RCV_MSG,
                                sizeof(*InP),
                                sizeof(*OutP),
                                reply_port,
                                MACH_MSG_TIMEOUT_NONE,
                                MACH_PORT_NULL);

    if (kr != MACH_MSG_SUCCESS) {
        mig_dealloc_reply_port(reply_port);
        return kr;
    }

    if (OutP->Head.msgh_id != 1301) {
        if (OutP->Head.msgh_id == MACH_NOTIFY_SEND_ONCE) {
            return MIG_SERVER_DIED;
        }
        return MIG_REPLY_MISMATCH;
    }

    return OutP->RetCode;
}

kern_return_t rawNACSign(
    mach_port_t server,
    uint32_t magic,
    uint64_t context,
    vm_offset_t data,
    mach_msg_type_number_t dataCnt,
    vm_offset_t *signature,
    mach_msg_type_number_t *signatureCnt
) {
    union {
        __Request__rawNACSign_t In;
        __Reply__rawNACSign_t Out;
    } Mess;

    __Request__rawNACSign_t *InP = &Mess.In;
    __Reply__rawNACSign_t *OutP = &Mess.Out;

    mach_port_t reply_port = mig_get_reply_port();

    memset(InP, 0, sizeof(*InP));
    InP->Head.msgh_bits = MACH_MSGH_BITS_COMPLEX | MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, MACH_MSG_TYPE_MAKE_SEND_ONCE);
    InP->Head.msgh_remote_port = server;
    InP->Head.msgh_local_port = reply_port;
    InP->Head.msgh_id = 1202;
    InP->Head.msgh_size = sizeof(*InP);

    InP->msgh_body.msgh_descriptor_count = 1;
    InP->data.address = (void *)data;
    InP->data.size = dataCnt;
    InP->data.deallocate = FALSE;
    InP->data.copy = MACH_MSG_VIRTUAL_COPY;
    InP->data.type = MACH_MSG_OOL_DESCRIPTOR;

    InP->NDR = NDR_RECORD;
    InP->magic = magic;
    InP->context = context;
    InP->dataCnt = dataCnt;

    kern_return_t kr = mach_msg(&InP->Head,
                                MACH_SEND_MSG | MACH_RCV_MSG,
                                sizeof(*InP),
                                sizeof(*OutP),
                                reply_port,
                                MACH_MSG_TIMEOUT_NONE,
                                MACH_PORT_NULL);

    if (kr != MACH_MSG_SUCCESS) {
        mig_dealloc_reply_port(reply_port);
        return kr;
    }

    if (OutP->Head.msgh_id != 1302) {
        if (OutP->Head.msgh_id == MACH_NOTIFY_SEND_ONCE) {
            return MIG_SERVER_DIED;
        }
        return MIG_REPLY_MISMATCH;
    }

    if (!(OutP->Head.msgh_bits & MACH_MSGH_BITS_COMPLEX)) {
        return ((mig_reply_error_t *)OutP)->RetCode;
    }

    *signature = (vm_offset_t)OutP->signature.address;
    *signatureCnt = OutP->signatureCnt;

    return KERN_SUCCESS;
}
