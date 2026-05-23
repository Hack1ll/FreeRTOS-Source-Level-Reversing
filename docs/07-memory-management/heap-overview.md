# Heap overview

이번 주제는 FreeRTOS의 heap allocator입니다.

지금까지 task, queue, semaphore 같은 커널 object를 봤다면, 이제 질문은
이것입니다.

```text
그 object들을 만들 메모리는 어디서 오나?
```

그 답이 FreeRTOS의 heap 구현입니다.

이번 장에서 보는 source file은 다음입니다.

- `FreeRTOS-Kernel/portable/MemMang/heap_1.c`
- `FreeRTOS-Kernel/portable/MemMang/heap_2.c`
- `FreeRTOS-Kernel/portable/MemMang/heap_3.c`
- `FreeRTOS-Kernel/portable/MemMang/heap_4.c`
- `FreeRTOS-Kernel/portable/MemMang/heap_5.c`

## Heap이 왜 필요할까?

FreeRTOS에서 task나 queue를 동적으로 만들면 메모리가 필요합니다.

예를 들어:

```c
xTaskCreate(...);
xQueueCreate(...);
xSemaphoreCreateBinary();
```

이런 API를 호출하면 내부적으로 이런 것들이 필요합니다.

```text
Task 생성
    -> TCB_t 메모리 필요
    -> stack 메모리 필요

Queue 생성
    -> Queue_t 메모리 필요
    -> queue storage 메모리 필요

Semaphore 생성
    -> 내부 queue object 메모리 필요
```

그림으로 보면:

```text
Application API
      |
      v
+------------------+
| xTaskCreate()    |
+------------------+
      |
      v
+------------------+      +------------------+
| TCB_t 필요        |      | Stack 필요       |
+------------------+      +------------------+
      |
      v
+------------------+
| heap에서 할당     |
+------------------+
```

즉 heap은 FreeRTOS가 커널 object를 만들 때 쓰는 메모리 창고입니다.

## 일반적인 heap 이미지

일반적으로 heap은 동적 메모리 공간입니다.

```text
Heap Memory

+------------------------------------------------+
|                                                |
|              free memory                       |
|                                                |
+------------------------------------------------+
```

무언가를 만들면 heap에서 일부를 떼어 씁니다.

```text
Before

+------------------------------------------------+
|                    free                        |
+------------------------------------------------+


allocate Task A TCB

+----------+-------------------------------------+
| TCB A    |                free                 |
+----------+-------------------------------------+
```

또 다른 것을 만들면 더 사용합니다.

```text
allocate Queue

+----------+------------+------------------------+
| TCB A    | Queue obj  |          free          |
+----------+------------+------------------------+
```

## FreeRTOS에는 heap 구현이 여러 개 있다

중요한 점은 이것입니다.

```text
FreeRTOS에는 heap allocator가 하나만 있는 게 아니다.
```

FreeRTOS는 여러 heap 구현을 제공합니다.

```text
FreeRTOS-Kernel/portable/MemMang/

heap_1.c
heap_2.c
heap_3.c
heap_4.c
heap_5.c
```

그런데 이 파일들을 전부 같이 쓰는 것은 아닙니다.

보통 application에서는 이 중 하나만 컴파일합니다.

```text
내 프로젝트에 맞는 heap_x.c 하나 선택
```

그림:

```text
+------------------+
| heap_1.c         |
+------------------+

+------------------+
| heap_2.c         |
+------------------+

+------------------+
| heap_3.c         |
+------------------+

+------------------+
| heap_4.c         |
+------------------+

+------------------+
| heap_5.c         |
+------------------+

        |
        v

프로젝트에서는 보통 하나만 선택
```

## 왜 heap이 여러 개일까?

임베디드 시스템은 환경이 제각각입니다.

어떤 시스템은 아주 단순합니다.

```text
부팅할 때 task, queue를 다 만들고
그 뒤에는 절대 free하지 않음
```

어떤 시스템은 동적으로 만들고 지워야 합니다.

```text
필요할 때 object 생성
필요 없어지면 object 삭제
```

어떤 시스템은 C 표준 라이브러리의 `malloc/free`를 쓰고 싶습니다.

```text
FreeRTOS heap 대신 libc malloc/free 사용
```

어떤 시스템은 메모리 영역이 여러 개입니다.

```text
RAM region 1
RAM region 2
external RAM
```

그래서 FreeRTOS는 하나의 universal allocator를 강제하지 않고, 여러 선택지를
줍니다.

```text
시스템 성격에 맞는 heap 구현을 고르세요.
```

## heap_1.c: 가장 단순한 방식

`heap_1.c`는 가장 단순하게 볼 수 있습니다.

```text
allocate만 가능
free 불가능
```

그림:

```text
Heap

+------------------------------------------------+
| free                                           |
+------------------------------------------------+

allocate A

+------+-----------------------------------------+
| A    | free                                    |
+------+-----------------------------------------+

allocate B

+------+-------+---------------------------------+
| A    | B     | free                            |
+------+-------+---------------------------------+
```

하지만 한 번 할당한 것을 되돌릴 수 없습니다.

```text
free(A) 불가능
```

이 방식은 이런 시스템에 맞습니다.

```text
시작할 때 필요한 object를 전부 만들고,
실행 중에는 삭제하지 않는 시스템
```

## heap_2.c: free는 있지만 합치지는 않음

`heap_2.c`는 할당과 해제를 지원합니다.

```text
allocate 가능
free 가능
```

하지만 인접한 빈 공간을 합치는 coalescing이 없습니다.

예를 들어:

```text
+------+-------+------+----------------+
| A    | B     | C    | free           |
+------+-------+------+----------------+
```

B를 free합니다.

```text
+------+-------+------+----------------+
| A    | free  | C    | free           |
+------+-------+------+----------------+
```

이제 C도 free합니다.

```text
+------+-------+------+----------------+
| A    | free  | free | free           |
+------+-------+------+----------------+
```

겉으로는 free가 이어져 있어도, allocator가 이를 큰 하나의 free block으로 합치지
않을 수 있습니다.

```text
fragmentation이 문제가 될 수 있음
```

## heap_3.c: C library malloc/free 사용

`heap_3.c`는 FreeRTOS 자체 heap 알고리즘을 쓰기보다 C library의 `malloc()`과
`free()`를 감쌉니다.

```text
pvPortMalloc()
    -> malloc()

vPortFree()
    -> free()
```

그림:

```text
FreeRTOS API
+----------------+
| pvPortMalloc() |
+--------+-------+
         |
         v
C library
+----------------+
| malloc()       |
+----------------+
```

이 방식은 C library allocator를 신뢰하고 사용하고 싶을 때 쓸 수 있습니다.

## heap_4.c: free list + coalescing

이번 프로젝트가 `heap_4.c`부터 보는 이유가 있습니다.

`heap_4.c`는 너무 복잡하지 않으면서도 allocator의 중요한 개념을 포함합니다.

```text
heap_4.c
    - allocation 가능
    - free 가능
    - free list 사용
    - adjacent free block coalescing 지원
```

여기서 중요한 단어는 두 개입니다.

```text
free list
    = 비어 있는 메모리 block들을 list로 관리

coalescing
    = 서로 붙어 있는 free block들을 합침
```

## free list란?

heap 전체를 한 덩어리로 보는 대신, 비어 있는 block들을 list로 관리합니다.

예를 들어 heap 상태가 이렇다고 합시다.

```text
Heap Memory

+------+-------+------+-------+----------------+
| A    | free  | B    | free  | free           |
+------+-------+------+-------+----------------+
```

free block만 따로 연결해서 관리합니다.

```text
Free List

+--------+     +--------+     +--------+
| free 1 | --> | free 2 | --> | free 3 |
+--------+     +--------+     +--------+
```

즉 allocator는 새 메모리 요청이 오면 free list를 보고 적당한 빈 block을 찾습니다.

```text
pvPortMalloc(size)
    |
    v
free list에서 충분히 큰 block 찾기
```

## allocation은 free block을 쪼갤 수 있다

큰 free block이 있다고 합시다.

```text
Before allocation

+----------------------------------------+
|                 free                   |
+----------------------------------------+
```

작은 object A를 할당합니다.

```text
allocate A
```

그러면 큰 free block을 둘로 나눌 수 있습니다.

```text
After allocation

+----------+-----------------------------+
| A        |            free             |
+----------+-----------------------------+
```

그림:

```text
free block
    |
    | allocate part
    v

+----------+-----------------------------+
| used     | remaining free              |
+----------+-----------------------------+
```

## free는 block을 다시 free list에 넣는다

사용하던 block A를 free한다고 합시다.

```text
Before free

+----------+-----------------------------+
| A        |            free             |
+----------+-----------------------------+
```

A를 free하면:

```text
After free

+----------+-----------------------------+
| free     |            free             |
+----------+-----------------------------+
```

이제 A였던 공간도 free list에 들어갑니다.

```text
Free List

+--------+     +--------+
| free A | --> | free B |
+--------+     +--------+
```

## coalescing: 붙어 있는 빈 block 합치기

`heap_4.c`의 중요한 특징은 coalescing입니다.

Coalescing은 서로 붙어 있는 free block을 하나로 합치는 것입니다.

예를 들어:

```text
Before coalescing

+----------+----------+------------------+
| free A   | free B   | used C           |
+----------+----------+------------------+
```

free A와 free B가 서로 붙어 있습니다.

그러면 하나로 합칠 수 있습니다.

```text
After coalescing

+---------------------+------------------+
|       big free      | used C           |
+---------------------+------------------+
```

왜 중요할까요?

작은 free block이 여러 개 있어도, 큰 allocation 요청은 실패할 수 있습니다.

```text
free total = 100 bytes

하지만

+----+----+----+----+
| 25 | 25 | 25 | 25 |
+----+----+----+----+

50 bytes 연속 공간이 없으면
50 bytes allocation 실패 가능
```

coalescing은 이런 fragmentation 문제를 줄입니다.

## fragmentation을 그림으로 보기

메모리가 이렇게 나뉘었다고 합시다.

```text
Heap

+------+-------+------+-------+------+
| used | free  | used | free  | used |
+------+-------+------+-------+------+
```

free 공간은 있지만 중간중간 끊겨 있습니다.

```text
free total은 충분해 보임
하지만 큰 연속 공간은 부족할 수 있음
```

이것이 fragmentation입니다.

```text
Fragmentation
    = 빈 공간이 여기저기 조각나서
      큰 연속 메모리를 만들기 어려운 상태
```

coalescing은 인접한 free block을 합쳐 fragmentation을 줄입니다.

```text
Before

+------+-------+-------+------+
| used | free  | free  | used |
+------+-------+-------+------+

After

+------+---------------+------+
| used | big free      | used |
+------+---------------+------+
```

## heap_5.c: 여러 메모리 영역

`heap_5.c`는 `heap_4.c`와 비슷한데, 여러 memory region을 사용할 수 있습니다.

예를 들어 시스템에 이런 메모리가 있다고 합시다.

```text
Internal RAM
External RAM
Special RAM region
```

그림:

```text
Memory Region 1

+----------------------+
| internal RAM heap    |
+----------------------+


Memory Region 2

+----------------------+
| external RAM heap    |
+----------------------+
```

`heap_5.c`는 이런 여러 region을 heap으로 다룰 수 있습니다.

```text
heap_5.c
    = 여러 메모리 영역을 하나의 allocator처럼 사용 가능
```

## heap 구현별 느낌 정리

```text
+----------+-------------------------------+
| heap_1   | malloc만 가능, free 불가       |
| heap_2   | malloc/free 가능, 병합 없음    |
| heap_3   | C library malloc/free 사용     |
| heap_4   | malloc/free + free list + 병합 |
| heap_5   | heap_4와 비슷 + 여러 region    |
+----------+-------------------------------+
```

조금 더 쉽게:

```text
heap_1
    = 한 방향으로만 쓰는 메모리 창고

heap_2
    = 반납은 되지만 빈 칸 정리가 약함

heap_3
    = FreeRTOS가 아니라 C library에게 맡김

heap_4
    = FreeRTOS가 직접 관리하고 빈 칸도 합침

heap_5
    = heap_4 기능 + 여러 메모리 구역 사용
```

## 왜 heap_4.c부터 공부할까?

`heap_1.c`는 너무 단순합니다.

```text
할당만 함
free 없음
coalescing 없음
```

Allocator를 공부하기에는 볼 게 적습니다.

`heap_4.c`는 적당히 작으면서 중요한 개념이 다 들어 있습니다.

```text
heap_4.c에서 볼 수 있는 것

+------------------+
| allocation       |
+------------------+

+------------------+
| free             |
+------------------+

+------------------+
| free list        |
+------------------+

+------------------+
| coalescing       |
+------------------+
```

그래서 FreeRTOS의 동적 kernel object allocation을 이해하기 좋은 첫 번째
대상입니다.

## kernel object allocation과 연결하기

앞에서 봤던 task 생성으로 다시 연결해봅시다.

```text
xTaskCreate()
    |
    v
TCB_t 필요
Stack 필요
    |
    v
pvPortMalloc()
```

Queue 생성도 비슷합니다.

```text
xQueueCreate()
    |
    v
Queue_t 필요
Queue storage 필요
    |
    v
pvPortMalloc()
```

Semaphore, mutex도 내부적으로 queue 구조를 쓰므로 비슷합니다.

```text
xSemaphoreCreateBinary()
    |
    v
Queue/Semaphore object 필요
    |
    v
pvPortMalloc()
```

즉 heap allocator는 FreeRTOS object들이 태어나는 기반입니다.

```text
Heap
  |
  +--> TCB_t
  |
  +--> task stack
  |
  +--> Queue_t
  |
  +--> semaphore object
  |
  +--> mutex object
```

## 전체 그림

```text
+------------------------------------------------+
|                  FreeRTOS Heap                 |
|------------------------------------------------|
|                                                |
|  +-----------+   +------------+   +----------+ |
|  | TCB_t     |   | Task Stack |   | Queue_t  | |
|  +-----------+   +------------+   +----------+ |
|                                                |
|  +----------------+   +----------------------+ |
|  | Semaphore obj  |   | remaining free memory| |
|  +----------------+   +----------------------+ |
|                                                |
+------------------------------------------------+
```

`heap_4.c` 관점에서는 free memory를 list로 관리합니다.

```text
Free List

+----------------+     +----------------+     +----------------+
| free block A   | --> | free block B   | --> | free block C   |
+----------------+     +----------------+     +----------------+
```

할당 요청이 오면:

```text
pvPortMalloc(size)
    |
    v
free list에서 적당한 block 찾기
    |
    v
block을 사용 중으로 표시
    |
    v
남는 공간은 free list에 유지
```

free 요청이 오면:

```text
vPortFree(ptr)
    |
    v
block을 free list에 되돌림
    |
    v
앞뒤 free block과 붙어 있으면 합침
```

## Heap을 공부할 때 중요한 관점

Heap 코드를 볼 때는 다음 질문을 잡고 읽으면 됩니다.

```text
1. heap memory는 어디에 있는가?
2. free block은 어떻게 표현되는가?
3. allocation 요청이 오면 어떤 free block을 고르는가?
4. block이 너무 크면 쪼개는가?
5. free할 때 free list에 어떻게 다시 넣는가?
6. 인접한 free block을 합치는가?
```

`heap_4.c`는 이 질문들에 대한 좋은 예시입니다.

## 최종 요약

```text
FreeRTOS heap
    = task, queue, semaphore 같은 kernel object를 만들 때 쓰는 동적 메모리 영역

FreeRTOS에는 heap 구현이 여러 개 있음
    = heap_1.c ~ heap_5.c

보통 하나만 선택해서 컴파일함

heap_1.c
    = allocation only, free 없음

heap_2.c
    = allocation/free 가능, coalescing 없음

heap_3.c
    = C library malloc/free 사용

heap_4.c
    = allocation/free
    = free list
    = adjacent free block coalescing

heap_5.c
    = heap_4 스타일
    = multiple memory regions 지원

heap_4.c를 먼저 보는 이유
    = 작지만 allocator의 핵심 개념을 잘 보여줌
```

가장 중요한 그림은 이것입니다.

```text
FreeRTOS object 생성
        |
        v
+------------------+
| pvPortMalloc()   |
+--------+---------+
         |
         v
+------------------+
| 선택된 heap_x.c  |
| allocator        |
+--------+---------+
         |
         v
+------------------+
| heap memory      |
+------------------+
```

한 문장으로 정리하면:

```text
FreeRTOS는 하나의 고정된 heap allocator를 강제하지 않고,
시스템 성격에 맞게 heap_1.c부터 heap_5.c 중 하나를 선택하게 한다.

그중 heap_4.c는 free list와 block 병합을 지원해서
동적 커널 object allocation을 이해하기 좋은 첫 allocator다.
```
