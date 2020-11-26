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
    char* diffPos;
	long timeBegin, timeEnd;
    struct stat st;
    int cpySize[9] = {3,13,50,100,512,1024,2048,4096,6144};
//    int cpySize[1] = {8192};
    pageSize = getpagesize();

    fd = open("./target.txt", O_RDWR);
    if(fd<0){
        printf("Open file error\n");
        exit(-1);
    }
    fstat(fd, &st);
    filesize = st.st_size;

//    src = mmap(NULL, filesize, PROT_READ | PROT_WRITE,
//                   MAP_PRIVATE, fd, 0);
//    if (src == MAP_FAILED)
//        errExit("mmap\n");

    src = calloc(1, filesize);
    if (src <0)
        errExit("malloc\n");

    dest = calloc(1, filesize);
    if (dest <0)
        errExit("malloc\n");
//    memcpy(dest,src,pageSize*6-1);
//    memset(dest+890,256,8);
//    *(dest+0) = 0;
//    *(dest+3) = 1;
//    *(dest+2) = 2;
//    *(dest+3) = 3;
//    *(dest+4) = 4;
//    *(dest+5) = 5;
//    *(dest+6) = 6;
//    *(dest+7) = 7;
    for(int j=0;j<9;j++){
        int cmpSize = cpySize[j];
        int cmpTime = 20<(cmpSize/10)?(cmpSize/10):20;
        int r;
        counter = 0;
    	timeBegin = get_nanos();
        srandom(timeBegin);
    	for(int i=0;i<cmpTime;i++){
    	    printf("counter: %d\n", counter);
            r = abs(random())%(cmpSize-1);
            int res = memcmp_avx2_asm(dest,src,r, &diffPos);
            if(res!=0){
                printf("cmpSize:%d\n", r);
            }
    		counter++;
    	}
    	timeEnd = get_nanos();
    	printf("memcmp time %ld, compare %d times, everage cmpare time %ld, comapre size %d\n",
    			timeEnd-timeBegin, counter, (timeEnd-timeBegin)/counter, cmpSize);
    }

//    for(int j=0;j<9;j++){
//        int cmpSize = cpySize[j];
////        int cmpSize = 512;
//        int cmpTime = 20<(cmpSize/10)?(cmpSize/10):20;
//        int r;
//        counter = 0;
//    	timeBegin = get_nanos();
//        srandom(timeBegin);
//    	for(int i=0;i<cmpTime;i++){
//            r = random()%(cmpSize-1);
////            r = 358;
//            *(dest+r) = 1;
////            printf("dest:%p, src:%p, cmpSize:%d, set Pos:%p\n", 
////                dest, src, cmpSize, dest+r);
//            int res = memcmp_avx2_asm(dest,src,cmpSize, &diffPos);
//            if(res==0 || (diffPos-dest)!=r){
//                printf("res:%d, retPos:%p, dest:%p, cmpSize:%d, set Pos:%d, current diff:%ld\n", 
//                    res, diffPos, dest, cmpSize, r, diffPos-dest);
//            }
//            *(dest+r) = 0;
//    		counter++;
//    	}
//    	timeEnd = get_nanos();
//    	printf("memcmp time %ld, compare %d times, everage cmpare time %ld, comapre size %d\n",
//    			timeEnd-timeBegin, counter, (timeEnd-timeBegin)/counter, cmpSize);
//    }

    return 0;
}
