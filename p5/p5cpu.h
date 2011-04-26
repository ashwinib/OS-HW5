#include<stdio.h>
#include<stdlib.h>
#include<string.h>
#include<pthread.h>
#include<limits.h>
#include<search.h>
#include"myatomic.h"

#define MAX_WORDS 100
#define MAX_FILES 10
typedef struct count_node{
        char word[20];
        int count;
        struct count_node *next,*pred,*succ;
}cnode;

extern pthread_mutex_t mtable;//Modify table
extern pthread_mutex_t order; 
extern pthread_t cpu;
extern cnode *highest;
extern cnode *lowest;
extern char *filenameCPU;

extern void init();
void pintf(char *buf);
void myprintf(char *s, int i);
extern void displayCount();
extern void* getWordCountsCPU();
extern void create_thread();
