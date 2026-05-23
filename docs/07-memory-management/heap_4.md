# heap_4

이번에는 `heap_4.c`를 빈 메모리 조각들을 list로 관리하고, 붙어 있는 빈 조각은
합쳐주는 allocator로 보면 됩니다.

핵심은 이것입니다.

```text
heap_4.c
    = malloc/free를 직접 구현한 작은 allocator

특징
    1. free list 사용
    2. free block마다 header가 있음
    3. 할당할 때 큰 free block을 쪼갤 수 있음
    4. free할 때 붙어 있는 free block을 합칠 수 있음
```

이번 장에서 보는 source file은 다음입니다.

- `FreeRTOS-Kernel/portable/MemMang/heap_4.c`

## heap_4.c가 관리하는 메모리

처음 heap은 큰 빈 메모리 덩어리입니다.

```text
Heap memory

+------------------------------------------------------+
|                      free                            |
+------------------------------------------------------+
```

`pvPortMalloc()`을 호출하면 이 공간 일부를 떼어 줍니다.

```text
pvPortMalloc(100)

+------------+-----------------------------------------+
| used 100   |                 free                    |
+------------+-----------------------------------------+
```

`vPortFree()`를 호출하면 사용하던 공간을 다시 빈 공간으로 돌려줍니다.

```text
vPortFree(ptr)

+------------+-----------------------------------------+
| free 100   |                 free                    |
+------------+-----------------------------------------+
```

그런데 allocator는 단순히 빈 공간이다만 알면 안 됩니다.

```text
이 free block의 크기는 얼마인가?
다음 free block은 어디인가?
```

이런 정보를 저장해야 합니다.

그래서 block header가 필요합니다.

## BlockLink_t는 free block의 이름표다

`heap_4.c`의 핵심 구조체는 `BlockLink_t`입니다.

개념적으로 이렇게 보면 됩니다.

```text
+----------------------+
| BlockLink_t header   |
|----------------------|
| next free block      |
| block size           |
+----------------------+
| usable bytes         |
|                      |
|                      |
+----------------------+
```

즉 free block 하나는 이렇게 생겼습니다.

```text
free block

+-------------------------+
| BlockLink_t             |
| - 다음 free block 위치   |
| - 이 block 크기          |
+-------------------------+
| 실제 사용 가능한 공간    |
| usable bytes            |
+-------------------------+
```

여기서 header는 allocator가 쓰는 metadata입니다.

사용자에게는 보통 header 뒤쪽 주소를 줍니다.

## 사용자 pointer는 header 뒤를 가리킨다

`pvPortMalloc()`이 메모리를 줄 때, allocator 내부 header까지 포함해서 주면
안 됩니다.

사용자는 실제 데이터 공간만 받아야 합니다.

```text
실제 heap block

+-------------------------+
| BlockLink_t header      |  <- allocator 전용
+-------------------------+
| user memory             |  <- 사용자에게 반환되는 주소
|                         |
+-------------------------+
```

따라서 `pvPortMalloc()`이 반환하는 pointer는 여기입니다.

```text
+-------------------------+
| BlockLink_t header      |
+-------------------------+
| user pointer ---------->|  usable memory
|                         |
+-------------------------+
```

그림으로 더 보면:

```text
allocator가 보는 block

+---------+---------------------------+
| header  | usable bytes              |
+---------+---------------------------+


사용자가 받는 pointer

          |
          v
+---------+---------------------------+
| header  | usable bytes              |
+---------+---------------------------+
```

즉:

```text
allocator:
    header부터 block을 봄

user:
    header 뒤의 usable memory만 봄
```

## free할 때는 user pointer에서 뒤로 돌아간다

사용자가 `vPortFree(ptr)`를 호출할 때 넘기는 `ptr`은 header가 아니라 usable
memory의 시작 주소입니다.

```text
ptr
 |
 v
+---------+---------------------------+
| header  | usable bytes              |
+---------+---------------------------+
```

그런데 allocator는 block 크기와 free list 연결 정보를 알아야 합니다.

그 정보는 header에 있습니다.

그래서 `vPortFree()`는 pointer에서 조금 뒤로 돌아가 header를 찾습니다.

```text
vPortFree(user pointer)

          user pointer
              |
              v
+-------------+-----------------------+
| header      | usable bytes          |
+-------------+-----------------------+
      ^
      |
allocator가 뒤로 이동해서 header 찾음
```

즉:

```text
user pointer
    |
    | sizeof(BlockLink_t)만큼 뒤로
    v
BlockLink_t header
```

이 구조가 malloc/free allocator에서 아주 흔한 패턴입니다.

## free list란?

`heap_4.c`는 빈 block들을 free list로 연결해 관리합니다.

heap에 사용 중인 block과 빈 block이 섞여 있다고 합시다.

```text
Heap memory

+----------+----------+----------+----------+----------+
| used A   | free B   | used C   | free D   | free E   |
+----------+----------+----------+----------+----------+
```

allocator는 free block만 연결해서 봅니다.

```text
Free list

+----------+       +----------+       +----------+
| free B   | ----> | free D   | ----> | free E   |
+----------+       +----------+       +----------+
```

여기서 연결 정보는 각 free block의 `BlockLink_t header` 안에 있습니다.

```text
free B

+----------------------+
| header               |
| next -> free D       |
| size                 |
+----------------------+
| usable bytes         |
+----------------------+
```

## heap_4.c는 free block을 주소 순서로 정렬한다

`heap_4.c`는 free list를 아무 순서로나 연결하지 않습니다.

보통 메모리 주소 순서로 정렬해둡니다.

```text
Heap address 낮음 ------------------------------> 높음

+----------+----------+----------+----------+----------+
| used A   | free B   | used C   | free D   | free E   |
+----------+----------+----------+----------+----------+
              |                       |          |
              v                       v          v

Free list:
free B ---------------> free D -----> free E
```

왜 주소 순서가 중요할까요?

붙어 있는 free block을 합치기 쉽기 때문입니다.

```text
주소 순서로 정렬되어 있으면
앞 block과 뒤 block이 실제 메모리에서 붙어 있는지 확인하기 쉽다.
```

## pvPortMalloc() 전체 흐름

`pvPortMalloc()`의 큰 흐름은 이렇습니다.

```text
pvPortMalloc()
    |
    v
처음 호출이면 heap 초기화
    |
    v
요청 size를 alignment에 맞게 조정
    |
    v
free list에서 충분히 큰 block 찾기
    |
    v
block이 너무 크면 쪼갬
    |
    v
header 뒤쪽 pointer를 사용자에게 반환
```

그림으로 보면:

```text
+-----------------------------+
| pvPortMalloc(size)          |
+-------------+---------------+
              |
              v
+-----------------------------+
| heap 초기화가 되었나?        |
+-------------+---------------+
              |
              v
+-----------------------------+
| size 정렬 및 header 크기 고려|
+-------------+---------------+
              |
              v
+-----------------------------+
| free list에서 block 찾기     |
+-------------+---------------+
              |
              v
+-----------------------------+
| 필요하면 block split         |
+-------------+---------------+
              |
              v
+-----------------------------+
| user pointer 반환            |
+-----------------------------+
```

## 첫 malloc 때 heap 초기화

처음에는 free list가 아직 준비되지 않았습니다.

```text
Before first malloc

Heap memory
+------------------------------------------------+
| raw memory                                     |
+------------------------------------------------+

Free list
not initialized
```

첫 `pvPortMalloc()` 호출 때 heap을 초기화합니다.

```text
After initialization

Heap memory
+------------------------------------------------+
| one big free block                             |
+------------------------------------------------+

Free list
+------------------------------------------------+
| one big free block                             |
+------------------------------------------------+
```

즉 처음에는 heap 전체가 하나의 큰 free block입니다.

## alignment가 왜 필요할까?

CPU는 특정 주소 정렬을 선호하거나 요구할 수 있습니다.

예를 들어 4-byte alignment가 필요하다고 하면, pointer는 이런 주소를 가져야
합니다.

```text
가능한 주소:
0x1000
0x1004
0x1008
0x100C
```

이런 주소는 안 좋을 수 있습니다.

```text
0x1001
0x1002
0x1003
```

그래서 allocator는 요청 크기를 alignment에 맞게 올립니다.

```text
사용자가 13 bytes 요청

alignment 때문에 실제 할당 크기:
16 bytes
```

그림:

```text
requested size = 13

+-------------+
| 13 bytes    |
+-------------+

aligned size = 16

+----------------+
| 16 bytes       |
+----------------+
```

즉:

```text
pvPortMalloc(13)
    -> 내부적으로는 16처럼 맞춰서 관리할 수 있음
```

## free block 찾기

free list가 이렇게 있다고 합시다.

```text
Free list

+----------+     +----------+     +----------+
| 32 bytes | --> | 128 bytes| --> | 64 bytes |
+----------+     +----------+     +----------+
```

사용자가 80 bytes를 요청합니다.

```text
pvPortMalloc(80)
```

allocator는 충분히 큰 block을 찾습니다.

```text
32 bytes
    -> 너무 작음

128 bytes
    -> 충분함

선택
```

그림:

```text
Request: 80 bytes

Free list

+----------+     +-----------+     +----------+
| 32       | --> | 128       | --> | 64       |
| too small|     | choose    |     | maybe    |
+----------+     +-----------+     +----------+
```

## block split: 큰 free block을 쪼개기

128 bytes free block에서 80 bytes만 필요하다고 합시다.

그러면 전체 128 bytes를 다 줄 수도 있지만, 남는 공간이 낭비됩니다.

그래서 쪼갭니다.

```text
Before split

+--------------------------------+
| free block 128                 |
+--------------------------------+
```

80 bytes를 할당하고, 나머지는 free block으로 남깁니다.

```text
After split

+--------------------+-----------+
| allocated 80       | free 48   |
+--------------------+-----------+
```

물론 실제로는 header 크기와 최소 block 크기 같은 조건도 고려합니다.

처음 이해할 때는 큰 block을 필요한 만큼 잘라 쓰고, 나머지는 다시 free list에
둔다고 보면 됩니다.

```text
큰 free block
    |
    | allocation
    v

+-------------+----------------+
| used part   | remaining free |
+-------------+----------------+
```

## pvPortMalloc() 결과

사용자는 allocated block의 header 뒤쪽을 받습니다.

```text
Allocated block

+-------------------------+
| BlockLink_t header      |
+-------------------------+
| user memory             |
|                         |
+-------------------------+

return pointer
      |
      v
user memory start
```

즉:

```text
pvPortMalloc()
    -> allocator metadata 뒤쪽 주소 반환
```

사용자는 header가 있다는 사실을 몰라도 됩니다.

## vPortFree() 전체 흐름

이번에는 free path입니다.

```text
vPortFree(ptr)
    |
    v
ptr에서 뒤로 이동해서 BlockLink_t header 찾기
    |
    v
block을 free 상태로 표시
    |
    v
free list에 주소 순서대로 삽입
    |
    v
앞뒤 free block과 붙어 있으면 합침
```

그림:

```text
+-----------------------------+
| vPortFree(ptr)              |
+-------------+---------------+
              |
              v
+-----------------------------+
| user ptr에서 header 복구     |
+-------------+---------------+
              |
              v
+-----------------------------+
| block을 free로 표시          |
+-------------+---------------+
              |
              v
+-----------------------------+
| free list에 삽입             |
+-------------+---------------+
              |
              v
+-----------------------------+
| adjacent block coalescing    |
+-----------------------------+
```

## free list에 다시 넣기

현재 heap이 이렇다고 합시다.

```text
Heap

+----------+----------+----------+----------+
| used A   | free B   | used C   | free D   |
+----------+----------+----------+----------+
```

free list는:

```text
free B -> free D
```

이제 `used C`를 free합니다.

```text
vPortFree(C)
```

C는 B와 D 사이에 있습니다.

```text
Heap

+----------+----------+----------+----------+
| used A   | free B   | free C   | free D   |
+----------+----------+----------+----------+
```

free list는 주소 순서에 맞게 C를 B와 D 사이에 넣습니다.

```text
Free list

free B -> free C -> free D
```

그림:

```text
Before

Free list:
+--------+       +--------+
| free B | ----> | free D |
+--------+       +--------+


Insert free C

Free list:
+--------+       +--------+       +--------+
| free B | ----> | free C | ----> | free D |
+--------+       +--------+       +--------+
```

## coalescing: 붙어 있는 free block 합치기

위 상황에서 B, C, D가 실제 메모리에서 붙어 있다고 합시다.

```text
Heap

+----------+----------+----------+----------+
| used A   | free B   | free C   | free D   |
+----------+----------+----------+----------+
```

이 경우 free block 3개로 둘 필요가 없습니다.

하나의 큰 free block으로 합칠 수 있습니다.

```text
After coalescing

+----------+-------------------------------+
| used A   | big free block                |
+----------+-------------------------------+
```

free list도 단순해집니다.

```text
Before

free B -> free C -> free D


After

big free block
```

## coalescing이 왜 중요할까?

메모리가 조각나면 전체 free memory가 충분해도 큰 allocation이 실패할 수
있습니다.

예를 들어 free memory가 총 120 bytes라고 합시다.

```text
Heap

+---------+---------+---------+---------+---------+
| free 40 | used    | free 40 | used    | free 40 |
+---------+---------+---------+---------+---------+

total free = 120
```

하지만 100 bytes 연속 공간은 없습니다.

```text
pvPortMalloc(100)
    -> 실패 가능
```

반대로 free block들이 붙어 있다면 합칠 수 있습니다.

```text
Before coalescing

+---------+---------+---------+
| free 40 | free 40 | free 40 |
+---------+---------+---------+

After coalescing

+-----------------------------+
| free 120                    |
+-----------------------------+
```

이제 100 bytes 할당이 가능합니다.

```text
pvPortMalloc(100)
    -> 성공 가능
```

즉:

```text
coalescing
    = fragmentation을 줄이는 방법
```

## heap_4.c가 bump allocator보다 흥미로운 이유

bump allocator는 아주 단순합니다.

```text
pointer가 한 방향으로 이동하면서 할당만 함
```

그림:

```text
Heap

+---------+---------+----------------------+
| used A  | used B  | free                 |
+---------+---------+----------------------+
                    ^
                    |
                 bump pointer
```

이 방식은 단순하지만 free와 재사용이 약합니다.

`heap_4.c`는 다릅니다.

```text
heap_4.c
    -> free 가능
    -> free list 관리
    -> block split 가능
    -> adjacent free block coalescing 가능
```

그래서 실제 allocator의 핵심 개념을 공부하기 좋습니다.

## heap_4.c 전체 구조 그림

```text
+--------------------------------------------------------------+
|                         Heap Memory                          |
|--------------------------------------------------------------|
|                                                              |
|  +----------+-----------+----------+-----------+             |
|  | used A   | free B    | used C   | free D    |             |
|  +----------+-----------+----------+-----------+             |
|                                                              |
+--------------------------------------------------------------+


Free List

+-------------------+        +-------------------+
| BlockLink_t B     | -----> | BlockLink_t D     |
| size = ...        |        | size = ...        |
+-------------------+        +-------------------+
| usable bytes      |        | usable bytes      |
+-------------------+        +-------------------+
```

할당할 때:

```text
pvPortMalloc()
    |
    v
free list에서 충분히 큰 block 찾기
    |
    v
필요하면 split
    |
    v
header 뒤 pointer 반환
```

해제할 때:

```text
vPortFree()
    |
    v
user pointer에서 header 복구
    |
    v
free list에 삽입
    |
    v
앞뒤 free block과 붙어 있으면 merge
```

## task와 queue 생성으로 연결하기

FreeRTOS에서 task를 만들면:

```text
xTaskCreate()
    |
    v
TCB_t 메모리 필요
Stack 메모리 필요
    |
    v
pvPortMalloc()
```

Queue를 만들면:

```text
xQueueCreate()
    |
    v
Queue_t 메모리 필요
Queue storage 필요
    |
    v
pvPortMalloc()
```

즉 `heap_4.c`는 이런 kernel object들이 태어날 메모리를 제공합니다.

```text
Heap memory
    |
    +--> TCB_t
    |
    +--> task stack
    |
    +--> Queue_t
    |
    +--> queue storage
    |
    +--> semaphore/mutex object
```

## heap_4.c를 읽을 때 붙잡을 질문

```text
1. BlockLink_t는 어디에 붙어 있는가?
2. user pointer는 header 뒤를 가리키는가?
3. free할 때 header를 어떻게 되찾는가?
4. free list는 어떤 순서로 정렬되는가?
5. malloc 때 큰 block을 쪼개는가?
6. free 때 앞뒤 block을 합치는가?
7. fragmentation을 어떻게 줄이는가?
```

이 질문들을 가지고 보면 `heap_4.c`가 훨씬 덜 무섭습니다.

## 최종 요약

```text
heap_4.c
    = FreeRTOS의 동적 메모리 allocator 중 하나
    = free list와 coalescing을 지원

BlockLink_t
    = free block의 header
    = 다음 free block pointer와 block size를 가짐

pvPortMalloc()
    = 요청 size를 alignment에 맞춤
    = free list에서 충분히 큰 block을 찾음
    = 필요하면 block을 split
    = header 뒤쪽 user pointer를 반환

vPortFree()
    = user pointer에서 뒤로 이동해 BlockLink_t를 복구
    = block을 free list에 다시 삽입
    = 인접한 free block과 coalescing

free list
    = free block들을 연결한 list
    = heap_4.c에서는 주소 순서가 중요함

coalescing
    = 붙어 있는 free block을 합쳐 큰 free block으로 만드는 것
    = fragmentation을 줄이는 데 도움
```

가장 중요한 그림은 이것입니다.

```text
Allocated block

+-------------------------+--------------------------+
| BlockLink_t header      | user memory              |
| allocator metadata      | returned pointer here    |
+-------------------------+--------------------------+
                          ^
                          |
                    pvPortMalloc() returns


vPortFree(ptr)

                          ptr
                          |
                          v
+-------------------------+--------------------------+
| BlockLink_t header      | user memory              |
+-------------------------+--------------------------+
          ^
          |
   allocator walks backward
   to recover header
```

한 문장으로 정리하면:

```text
heap_4.c는 heap 안의 빈 메모리 block들을 header가 달린 free list로 관리하고,
malloc 때 적당한 block을 잘라 주며,
free 때 block을 다시 넣고 주변 빈 block과 합쳐 fragmentation을 줄이는 allocator다.
```
