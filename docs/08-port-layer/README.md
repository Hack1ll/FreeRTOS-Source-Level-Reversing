# Port layer

The FreeRTOS kernel is portable because the non-portable parts are pushed into a
small port layer.

이 파트는 GCC ARM Cortex-M4F port를 기준으로 봅니다. Common kernel code는
task list와 scheduler state를 다루고, port layer는 interrupt priority, initial
stack frame, SysTick, PendSV, register save/restore를 다룹니다.

The first target is:

1. [GCC ARM Cortex-M4F port](gcc-arm-cm4f.md)

다른 architecture port를 보기 전에 이 파일 하나를 깊게 읽는 편이 좋습니다.
