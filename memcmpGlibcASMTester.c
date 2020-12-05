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

//#define memSize 33554432    //32M
//536870912       //512M
//1073741824      //1G
#define memSize 4294967296      //4G
//#define memSize 687194767360    //10G 
static long get_nanos() {
    struct timespec ts;
    timespec_get(&ts, TIME_UTC);
    return (long)ts.tv_sec * 1000000000L + ts.tv_nsec;
}

extern int memcmp_avx2_asm(const void *s1, const void *s2, size_t n, void* firstDiffPos);	
#define errExit(msg)    \
        do { perror(msg); exit(EXIT_FAILURE); \
                    } while (0)

int main(void) {
    int status, pkey, counter = 0, pageSize, fd, filesize;
    char *dest, *src;
    char *destTmp, *srcTmp;
    char* diffPos;
	unsigned long long timeBegin, timeEnd;
    struct stat st;
    unsigned long tail;
    int cpySize[26] = {3,13,50,100,512,1024};
    for(int i=6;i<26;i++){
        cpySize[i] = cpySize[i-1]+4096;
    }
    pageSize = getpagesize();

    src = calloc(1, memSize);
    if (src <0)
        errExit("malloc\n");
    tail = (unsigned long)src + memSize - 6245 - cpySize[25];

    dest = calloc(1,  memSize);
    if (dest <0)
        errExit("malloc\n");

    printf("time(ns)\n");
    for(int j=0;j<26;j++){
        int cmpSize = cpySize[j];
        counter = 0;
    	timeBegin = get_nanos();
        destTmp = dest;
        srcTmp = src;
    	for(;(unsigned long)srcTmp<=tail;
               destTmp = destTmp+cmpSize+4097,srcTmp=srcTmp+cmpSize+4097){
            int res = memcmp_avx2_asm(destTmp,srcTmp,cmpSize, &diffPos);
            if(res!=0){
                printf("cmp different, cmpSize:%d\n", cmpSize);
            }
    		counter++;
    	}
    	timeEnd = get_nanos();
    	printf("\tmemcmp consume time %10lld, ", timeEnd-timeBegin);
    	printf("compare %10d times, ", counter);
    	printf("everage cmpare time %6lld, ", (timeEnd-timeBegin)/counter);
    	printf("comapre size %7d\n", cmpSize);
    }

    return 0;
}
