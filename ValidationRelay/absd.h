#ifndef _absd_user_
#define _absd_user_

#include <mach/kern_return.h>
#include <mach/port.h>
#include <mach/message.h>
#include <mach/vm_types.h>

#ifdef __cplusplus
extern "C" {
#endif

kern_return_t rawNACInit(
    mach_port_t server,
    uint32_t magic,
    vm_offset_t cert,
    mach_msg_type_number_t certCnt,
    uint64_t *context,
    vm_offset_t *session_request,
    mach_msg_type_number_t *session_requestCnt
);

kern_return_t rawNACKeyEstablishment(
    mach_port_t server,
    uint32_t magic,
    uint64_t context,
    vm_offset_t session_response,
    mach_msg_type_number_t session_responseCnt
);

kern_return_t rawNACSign(
    mach_port_t server,
    uint32_t magic,
    uint64_t context,
    vm_offset_t data,
    mach_msg_type_number_t dataCnt,
    vm_offset_t *signature,
    mach_msg_type_number_t *signatureCnt
);

#ifdef __cplusplus
}
#endif

#endif /* _absd_user_ */
