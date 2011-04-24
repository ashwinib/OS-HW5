#include<stdio.h>
#include<stdlib.h>
#include<string.h>
#include<pthread.h>
#include<limits.h>
#include<search.h>
#include"myatomic.h"

#define MAX_WORDS 100
#define MAX_FILES 10

pthread_mutex_t mtable = PTHREAD_MUTEX_INITIALIZER;//Modify table
pthread_mutex_t order = PTHREAD_MUTEX_INITIALIZER;

void pintf(char *buf){
int i=0;
while(buf[i]!='\0'){i++;}
write(1,buf,i);
}
void myprintf(char *s, int i) {
  char out[80];

  sprintf(out, s, i);
  write(1, out, strlen(out));

}

typedef struct count_node{
	char word[20];
	int count;
	struct count_node *next,*pred,*succ;	
}cnode;

cnode *highest,*lowest;

void displayCount(){
	cnode *ptr;
	pthread_mutex_lock(&order);
	ptr=highest;
//	pintf("\n***Imhere");
	while(ptr!=NULL){	
		printf("%s:[%d]\n",ptr->word,ptr->count);
		ptr=ptr->succ;
	}
//	pintf("\n***Imhere");
	pthread_mutex_unlock(&order);
}

void* getWordCounts(char *filename){
	FILE *fp;
	char line[LINE_MAX] ;//2048
	char *copy;
	char delims[] = " .!";
	char *result = NULL,*saveptr,res[20];
	int temp,temp2;
	cnode *cptr = NULL;
	int id, sum;
	ENTRY item;
	ENTRY *found_item;

	if(strstr(filename,"1")!=NULL) id=1;
	if(strstr(filename,"2")!=NULL) id=2;
//	myprintf(filename,0);
//	pintf("\nFile Read..");
//	pintf(filename);
do{
	cptr = NULL;result = NULL;
	fp = fopen(filename,"r");
	if(fp == NULL) {
	        perror("failed to open ");perror(filename);
        	return ;//EXIT_FAILURE;
	}
	while (fgets(line, LINE_MAX +1, fp)) {
	        //myprintf(line,1);
//		pintf("\n");
//		pintf(line);
	
		result = strtok_r( line, delims ,&saveptr);
		while( result != NULL ) {
//			pintf("\nWord token:");
//  			pintf( result );
			if(strcmp(result,"\n")==0)break;
			sum  =0 ;
/*			for( temp = 0; result[ temp ]; temp++)
			  {result[temp] = (result[temp] > 64 && result[temp] < 91) ? result[temp]+32 : result[temp]; sum+=result[temp];}*/
			item.key = strdup(result);
			pthread_mutex_lock(&mtable);

			//pintf("\nWord token:");myprintf("\t%d",sum);
  			//pintf(item.key);
			if((found_item = hsearch(item,FIND))==NULL){ //No entry at this hash
				cptr = (cnode*) malloc (sizeof(cnode));
				strcpy(cptr->word,result);
				cptr->count = 1;
				cptr->next = NULL;
				item.data = cptr;

				//Add yourself(cptr) to the tail
//				pintf("\nAcquiring lock");
			 	pthread_mutex_lock(&order);
				if(highest == NULL) {highest = lowest =cptr; cptr->succ = NULL; cptr->pred=NULL;}
				else{
//				pintf("\nSitting at the end");
				lowest->succ = cptr;
				cptr->pred=lowest;
				cptr->succ=NULL;
				lowest = cptr;
				}
			 	pthread_mutex_unlock(&order);
//				pintf("\nReleasing lock");
				//pintf("\nAdding to hash : ");
//				pintf(item.key);
//				pintf("|");myprintf(" %d",id);

				hsearch(item,ENTER);//Cannot use compare and swap here as its internal to Hash
				pthread_mutex_unlock(&mtable);
			}
			else{	//Entry found 
				pthread_mutex_unlock(&mtable);
				/*pintf("\n** ");
				pintf(result);
				pintf(" was already there.");*/

				//CHECK FOR COLLISION
				cnode *nptr ,*optr; //next-ptr and old-ptr
				cnode *ptr,*me;
				nptr = me = (cnode *)found_item->data;
				optr=nptr;
				cptr = (cnode*) malloc (sizeof(cnode));
				strcpy(cptr->word,result);
				cptr->count = 1;
				cptr->next = NULL;
//				pintf("\nGoing for collision check now.");
				while(strcmp(nptr->word,result)!=0 && 
					(optr=compare_and_swap_ptr(&(nptr->next),cptr,NULL)))//COLLISION CHECK
					nptr=optr;
				if(strcmp(nptr->word,result)==0 && optr!=NULL){//there was no new node added hence increment
					//USING COMPARE &SWAP to increment in nptr
					temp =2;temp2= 1;
//					pintf("\nGonna simple icrement");
					while(temp2!=compare_and_swap(&(((cnode*)found_item->data)->count),temp,temp2)){//find the count and increment;
					  //myprintf("\nItwas %d",temp2);
					  temp++;temp2++;
					}


					//ORDERING LOGIC
					 pthread_mutex_lock(&order);
//					pintf("\nAcquiring lock2");
					if(highest!=me){
  					  //highest is decided but since my count has changed i need to move
				 		ptr = me->pred;
//						pintf("\nIm not the highest but movint to right position");
						while(ptr!=NULL && me->count>ptr->count){ptr=ptr->pred;}
						if(ptr==NULL){//highest
//							pintf("\nSitting at the top");
							me->pred->succ = me->succ;
							if(me!=lowest) me->succ->pred = me->pred; else lowest= me->pred;
							me->succ = highest;
							highest->pred = me;
							me->pred = NULL;
							highest = me;
							//pintf("\nMy succ=");pintf(me->succ->word);
						}else if(ptr == me->pred && me->count>ptr->count){//neighbor and still greater
//							pintf("\nSwapping with neighbor");
							ptr->succ = me->succ;
							if(me!=lowest)me->succ->pred = ptr; else lowest =ptr;
							ptr->pred->succ = me;
							me->pred = ptr->pred;
							ptr->pred=me;
							me->succ = ptr;
//							pintf("\nMy pred=");pintf(me->pred->word);
							//pintf("\nMy succ=");pintf(me->succ->word);
						}else if(ptr != me->pred){//somewhere with diff count
//							pintf("\nSitting in the middle");
							me->pred->succ = me->succ;
							if(me!=lowest)me->succ->pred = me->pred;else lowest = me->pred;
							ptr->succ->pred =me;
							me->succ= ptr->succ;
							me->pred = ptr;
							ptr->succ = me;
//							pintf("\nMy pred=");pintf(me->pred->word);
							//pintf("\nMy succ=");pintf(me->succ->word);
						}
					}	
//					pintf("\nReleasing lock2");
					pthread_mutex_unlock(&order);
					

//					myprintf("\nIncremented to : %d",((cnode*)found_item->data)->count);
				}
				else{//A new node was added due to collision but only remains to be ordered. :at the tail.
					//pintf("\n**U are not supposed to be here**");
//					pintf("\nAcquiring lock3");
				 	pthread_mutex_lock(&order);
//					pintf("\nSitting at the end");
					lowest->succ = me;
					me->pred=lowest;
					me->succ = NULL;
					lowest = me;
				 	pthread_mutex_unlock(&order);
//					pintf("\nReleasing lock3");
				}
			}

			result = strtok_r( NULL, delims , &saveptr);
		}
    	}
	fclose(fp);
	free(filename);
	filename = (char*) malloc (LINE_MAX * sizeof(char));
	}while(scanf("%s",filename)!=EOF);
//	pintf("\nClosing File");
	return ;// EXIT_SUCCESS;
}

int main(int argc, char **argv){
	int pi =0,i;
	char *filename;
	int task_threads = 0;
	pthread_t p[MAX_FILES];
	//filename = (char*) malloc (LINE_MAX * sizeof(char));
	hcreate(MAX_WORDS);
	ENTRY item,*found_item;
	cnode *ptr;
	highest = NULL;
	
	
	while(task_threads<2){//ONLY TWO TASK THREADS 
		filename = (char*) malloc (LINE_MAX * sizeof(char));
		scanf("%s",filename);
//		pintf("\nAbout to read ");
//		pintf(filename);

		pthread_create(&p[pi],NULL,(void *)&getWordCounts,(void*)filename);
		pi++;
		task_threads++;

		//printf("\nFound %s",filename);
	}
	for(i =0 ;i<pi;i++)
	pthread_join(p[i],NULL);
	
	//Display Hash
	/*item.key = "this";
	pintf("Gonna look for THIS");
	found_item = hsearch(item,FIND);
	myprintf("\n\nCount of THis is : %d",((cnode*)found_item->data)->count);*/
	displayCount();
}


