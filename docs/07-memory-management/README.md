# Memory management

FreeRTOS does not force one allocator on every application.

대신 `portable/MemMang/` 아래에 여러 heap implementation을 제공하고, application이
하나를 골라 링크합니다. 이 파트에서는 그중 `heap_4.c`를 먼저 봅니다. Free와
인접 block 병합을 지원하기 때문에 allocator의 기본 구조를 공부하기에 좋습니다.

The order in this part is:

1. [Heap overview](heap-overview.md)
2. [heap_4](heap_4.md)
3. [Allocation flow](allocation-flow.md)

Task와 queue는 그냥 생겨나지 않습니다. Dynamic allocation을 쓰는 설정에서는
결국 `pvPortMalloc()`을 지나갑니다.

