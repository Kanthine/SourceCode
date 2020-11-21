//
//  YLMsgSend.h
//  Hook
//
//  Created by 苏沫离 on 2020/11/19.
//

#ifndef YLMsgSend_h
#define YLMsgSend_h

static int method_min_duration = 1 * 1000; // 1 milliseconds

void yl_msgSend_start(char* log_path);
void yl_msgSend_stop_print(void);
void yl_msgSend_resume_print(void);

#endif /* YLMsgSend_h */
