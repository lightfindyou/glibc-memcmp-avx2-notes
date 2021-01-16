#include <assert.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>

typedef char __u8;

#define memSize 30      //1K
//#define memSize 1024      //1K
//#define memSize 33554432    //32M
//536870912       //512M
//1073741824      //1G
//#define memSize 1073741824      //1G
//#define memSize 4294967296      //4G
#define TEST_NR 300
//#define memSize 687194767360    //10G 
static long get_nanos() {
    struct timespec ts;
    timespec_get(&ts, TIME_UTC);
    return (long)ts.tv_sec * 1000000000L + ts.tv_nsec;
}

void printMem(void* mem, int lineNr){
		int i=0;
		for(;i<lineNr;i++){
			__u8* id = (__u8*)(mem+16*i);
			printf("%02x%02x %02x%02x %02x%02x %02x%02x %02x%02x %02x%02x %02x%02x %02x%02x\n",
				 *(__u8*)((unsigned long long)id+0), *(__u8*)((unsigned long long)id+1),
				 *(__u8*)((unsigned long long)id+2), *(__u8*)((unsigned long long)id+3),
				 *(__u8*)((unsigned long long)id+4), *(__u8*)((unsigned long long)id+5),
				 *(__u8*)((unsigned long long)id+6), *(__u8*)((unsigned long long)id+7),
				 *(__u8*)((unsigned long long)id+8), *(__u8*)((unsigned long long)id+9),
				 *(__u8*)((unsigned long long)id+10), *(__u8*)((unsigned long long)id+11),
				 *(__u8*)((unsigned long long)id+12), *(__u8*)((unsigned long long)id+13),
				 *(__u8*)((unsigned long long)id+14), *(__u8*)((unsigned long long)id+15));
		}
}

void printLine(void* mem, int charNum){
    int lineNr = charNum/16+((charNum)%16)?1:0;
    printMem(mem, lineNr);
}

extern int memcmp_avx2_asm(const void *s1, const void *s2, size_t n, void* firstDiffPos);	
#define errExit(msg)    \
        do { perror(msg); exit(EXIT_FAILURE); \
                    } while (0)

int main(void) {
    char * const dest = malloc(memSize);;
    char * const src = malloc(memSize);;
    char *destCmp, *srcCmp;
    char* diffAddr;
    int cmpSize;
	unsigned long long timeBegin, timeEnd;

    if (src <0 || dest <0)
        errExit("malloc\n");

    memcpy(src, dest, memSize);

    srandom(get_nanos());
    for(int j=0;j<TEST_NR;j++){
        do{
            cmpSize = random()%memSize;
        }while(cmpSize == 0);

//        cmpSize = 7;
        int cmpOffset = random()%(memSize-cmpSize);
        int diffPos = random()%cmpSize;

        char *diffp = dest+cmpOffset+diffPos;
        char newCon;
        do{
            newCon = random()%100;
        }while(newCon==*diffp);
        *diffp = newCon;

        printf("dest Mem:\n");
        printLine(dest+cmpOffset, cmpSize);
        printf("src Mem:\n");
        printLine(src+cmpOffset, cmpSize);
        int res = memcmp_avx2_asm(dest+cmpOffset, src+cmpOffset, cmpSize, &diffAddr);
        if(res!=0){
            if(diffAddr != diffp){
                printf("diffAddr:%p, cmpSrc:%p, destSrc: %p, cmpLen:%d, correct diffAddr:%p\n",
                    diffAddr, src+cmpOffset, dest+cmpOffset, cmpSize, diffp);
                printf("diffOffset:%ld, correct diff Offset:%d\n",
                    diffAddr-(dest+cmpOffset), diffPos);
                printf("Wrong\n");
                return -1;
            }
            printf("%4d. Pass\n", j);
        }else{
            printf("Wrong, content same.\n");
            return -1;
        }
        memcpy(src, dest, memSize);
    }

    return 0;
}
