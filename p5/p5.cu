#include<stdio.h>
#include<stddef.h>
#include<search.h>
#include<signal.h>
#include<device_functions.h>
#include "util/cuPrintf.cu"
#include<sys/time.h>
extern "C"{
#include "p5cpu.h"
}
#define HANDLE_ERROR( err ) {if (err != cudaSuccess) { \
        printf( "%s in %s at line %d\n", cudaGetErrorString( err ), __FILE__, __LINE__ ); \
        exit( EXIT_FAILURE );}}

#define MAX_FILE_SIZE 200
#define MAX_HASH_ENTRIES 200
#define M 100
#define BAGSIZE 10

__global__ void getWordCounts(char *fileArray,int *countArray,int *fileSize,char *wordhashtable, int *nextPtr, int *lock){
  unsigned int i = blockIdx.x * blockDim.x + threadIdx.x;
  int ind,word_started =0 ,count =0;
  int found;
  int hashvalue;
  char *ptr,*wptr,*temp;
  ptr = &fileArray[i*MAX_FILE_SIZE];
  int  tempi=0,tempi2;


  for(ind =0;ind<fileSize[i];ind++){
//    if(ptr[ind]>64&&ptr[ind]<91) ptr[ind]+=32;   //ADD FOR CASE INSENSITIVE
    if(ptr[ind]!=' '&&ptr[ind]!='.'&&ptr[ind]!='!'&&ptr[ind]!='\n')
      if(word_started!=1) {
	word_started = 1;
	hashvalue = ptr[ind];//>64&&ptr[ind]<91) ? ptr[ind]+32:ptr[ind];//temp addition else do only assignemnt
	wptr = &ptr[ind];
      }
      else{//Middle of the word
	hashvalue+= ptr[ind];//>64&&ptr[ind]<91) ? ptr[ind]+32:ptr[ind];
      }
    if(word_started)
      if(ptr[ind]==' '||ptr[ind]=='.'||ptr[ind]=='!'||ptr[ind]=='\n'){
        word_started = 0;
	hashvalue = hashvalue % M;// 10 here is hashtable size M
//	cuPrintf("\n%d : Found token %c%c%c ; hash=%d",i,wptr[0],wptr[1],wptr[2],hashvalue);

	/*CHECK IF FOUND IN HASH
	*---------------------------
	*/	
	//lock -hashvalue
//	cuPrintf("\n%d : 1locking  %d",i,hashvalue);
	while(!atomicCAS(&lock[hashvalue],0,1));
	if(wordhashtable[hashvalue*20]=='\0'){//Not found in Hash

	  temp = &wordhashtable[hashvalue*20];
	  tempi =0;
	  while(&wptr[tempi]!=&ptr[ind])//Entering in hash table
		{temp[tempi]= wptr[tempi];
		tempi++;}
	//unlock -hash value
	//  if(!atomicCAS(&lock[hashvalue],1,0)) atomicAdd(&countArray[hashvalue],999);//error detection
//	cuPrintf("\n%d : 1UNlocking  %d",i,hashvalue);
	atomicExch(&lock[hashvalue],0);
//	cuPrintf("\tUpdating for(1) : %d",hashvalue);
	  atomicAdd(&countArray[hashvalue],1);//count

	}
	else{

	  /*CHECK IF COLLISION
	   *---------------------*/
	  tempi =hashvalue;found = -1;
	 /*Check word*/
	  while(nextPtr[tempi]!=-1||found==-1){
//	    cuPrintf("\n%d: next check : %d",i,tempi);
	    tempi2 = 0;
	    found =1;
	    temp = &wordhashtable[tempi*20];
//	    cuPrintf("\n%d: with word : %c%c%c",i,temp[0],temp[1],temp[2]);
	    while(&wptr[tempi2]!=&ptr[ind]){
	      if(temp[tempi2]!=wptr[tempi2]) {found =0;break;}
	      tempi2++;
	    }
	    if(temp[tempi2]!='\0') found =0;
	    if(found) break;
	    if(nextPtr[tempi]!=-1){
//		cuPrintf("\n%d : 2going to next link   %d",i,nextPtr[tempi]);
//		cuPrintf("\n%d : 2Unlocking  %d",i,tempi);found =-1;
		found =-1;
	    	//unlock - tempi
	    	atomicExch(&lock[tempi],0);
	       	tempi = nextPtr[tempi];      
		//lock - tempi
//		cuPrintf("\n%d : 2locking  %d",i,tempi);
		while(!atomicCAS(&lock[tempi],0,1));
	    }
	  }

	  if(found){ /*COLLISION BUT FOUND*/
	    //unlock - tempi
//		cuPrintf("\n%d : 3Unlocking  %d",i,tempi);
//	cuPrintf("\tUpdating for(2) : %d",tempi);
	    atomicExch(&lock[tempi],0);
	    atomicAdd(&countArray[tempi],1);
		}

	  else{   /*COLLISION AND ENTRY NOT FOUND*/
	    tempi2 =0;
	    //lock - M+tempi2
//		cuPrintf("\n%d : 3locking  %d",i,M+tempi2);
	    while(!atomicCAS(&lock[M+tempi2],0,1));
	    while(wordhashtable[(M+tempi2)*20]!='\0' && (tempi2+M)<MAX_HASH_ENTRIES) {
//		cuPrintf("\n%d : 4Unlocking  %d",i,M+tempi2);
		//unlock - M+tempi2
	        atomicExch(&lock[M+tempi2],0);
		tempi2++;//10 = M; tempi2 holds location in hast tab;e
		//lock - M+tempi2
//		cuPrintf("\n%d : 4locking  %d",i,M+tempi2);
	    	while(!atomicCAS(&lock[M+tempi2],0,1));
	    }
	    if((tempi2+M) < MAX_HASH_ENTRIES){
//		cuPrintf("\n%d : updating nextPtr at %d to %d",i,tempi,M+tempi2);
	    	nextPtr[tempi] = tempi2+M;
	    	//unlock - tempi
//		cuPrintf("\n%d : 5Unlocking  %d",i,tempi);
	    	atomicExch(&lock[tempi],0);
		
		tempi=0;//tempi holds the location where last hash was found not needed anymore.
	        temp = &wordhashtable[(M+tempi2)*20];
		while(&wptr[tempi]!=&ptr[ind]) //Entering in hash table
			{temp[tempi]= wptr[tempi]; 
			tempi++;}

	//cuPrintf("\tUpdating for(3) : %d",tempi2+M);
		atomicAdd(&countArray[tempi2+M],1);
	    }//count*/
	   //unlock - tempi
//		cuPrintf("\n%d : 6Unlocking  %d",i,tempi);
	    atomicExch(&lock[tempi],0);//succeeds when there was no space in hash
	    //tryunlock = M+tempi2
//		cuPrintf("\n%d : 7UNlocking  %d",i,M+tempi2);
	    atomicExch(&lock[M+tempi2],0);
	  }

	}//else of collision detection
	count++;
      }//if ptr = delimiter...
  }//for
}

int main(int argc,char **argv){
  char *filename=NULL;//Limiting no if files
  char *fileArray;
  char *dfileArray;
  char *dfileArray1;
  int *countArray;
  int *dcountArray;
  int *fileSize;
  int *dfileSize;
  int *dfileSize1;
  char *hashtable; 
  char *dhashtable; 
  int *nextPtr;
  int *dnextPtr;
  int *dlock;
  int noOfFiles=0;
  FILE *fp;
  char c;
  int eof;
  cnode *cnode_ptr; 

  struct timeval tempo1, tempo2;
  long elapsed_sec;

  cudaStream_t stream,stream2;
  HANDLE_ERROR( cudaStreamCreate(&stream) );
  HANDLE_ERROR( cudaStreamCreate(&stream2) );

  init();

  int readComplete =1 ,noOfReads=0 , redArea =0 ;

 // initialize cuPrintf
  cudaPrintfInit();


  char *temp;int itemp=0,itemp2 =0 ,max,maxind;
  filename =(char*) malloc (10*sizeof(char));
  //fileArray=(char*) malloc(10*MAX_FILE_SIZE*sizeof(char));
  cudaHostAlloc((void**)&fileArray,10*MAX_FILE_SIZE*sizeof(char),cudaHostAllocDefault);
 // cudaMallocHost((void**)&fileArray,10*MAX_FILE_SIZE*sizeof(char));
  countArray =(int*) malloc (MAX_HASH_ENTRIES*sizeof(int));//corresponding counts of words
  //fileSize =(int*) malloc (10*sizeof(int));
  cudaHostAlloc((void**)&fileSize,10*sizeof(int),cudaHostAllocDefault);
  //cudaMallocHost((void**)&fileSize,10*sizeof(int));
  hashtable=(char*) malloc(20*MAX_HASH_ENTRIES*sizeof(char));
  nextPtr = (int*) malloc (MAX_HASH_ENTRIES*sizeof(int));

  cudaMalloc((void**)&dfileArray,10*MAX_FILE_SIZE*sizeof(char));
  cudaMalloc((void**)&dfileArray1,10*MAX_FILE_SIZE*sizeof(char));
  cudaMalloc((void**)&dcountArray,MAX_HASH_ENTRIES*sizeof(int));//corresponding counts of words
  cudaMalloc((void**)&dfileSize,10*sizeof(int));
  cudaMalloc((void**)&dfileSize1,10*sizeof(int));
  cudaMalloc((void**)&dhashtable,20*MAX_HASH_ENTRIES*sizeof(char));//20-max word size 500-max words
  cudaMalloc((void**)&dnextPtr,MAX_HASH_ENTRIES*sizeof(int));//corresponding counts of words
  cudaMalloc((void**)&dlock,MAX_HASH_ENTRIES*sizeof(int));//corresponding counts of words

  cudaMemset(dcountArray,0,MAX_HASH_ENTRIES*sizeof(int));
  cudaMemset(dhashtable,'\0',20*MAX_HASH_ENTRIES*sizeof(char));
  cudaMemset(dnextPtr,-1,MAX_HASH_ENTRIES*sizeof(int));
  cudaMemset(dlock,0,MAX_HASH_ENTRIES*sizeof(int));

gettimeofday(&tempo1, NULL);

while(1)  {
 noOfFiles=0; 
  while(noOfReads<BAGSIZE&&(!readComplete || (eof=scanf("%s",filename))!=EOF)){
  //  printf("\nAttempting to open %s %d",filename,readComplete);
    if(readComplete){
      fp = fopen(filename,"r");
      if(fp == NULL) {
	        perror("failed to open sample.txt");
        	exit(0) ;//EXIT_FAILURE;
      }
    }
    memset(&fileArray[noOfFiles*200],'\0',MAX_FILE_SIZE);
    itemp = fread(&fileArray[noOfFiles*200],sizeof(char),MAX_FILE_SIZE,fp);
    //printf("\n->%s\n",&fileArray[noOfFiles*200]);
    if(feof(fp)) readComplete = 1;
    else readComplete =0 ;


//printf("\nGonna check edge case:(readComplete=%d)\n",readComplete);
    if(!readComplete){//handle edge
	c = fileArray[(noOfFiles*200)+199];itemp2 =199 ;
//			printf("noOfFiles=%d\n%c%c--",noOfFiles,c,fileArray[(noOfFiles*200)+198]);
	if(c>64 && c<91 || c>96 && c<123){
		while(c!=' '&&c!='.'&&c!='!'&&c!='\n'){
//			printf("%c",c);
		  fileArray[(noOfFiles*200)+itemp2]=' ';
		  itemp2--;
		  c = fileArray[(noOfFiles*200)+itemp2];
		}
//		printf("moving back %d\n",itemp2-200);
		fseek(fp,itemp2-200,SEEK_CUR);
	}
    }

    fileSize[noOfFiles]=itemp;//(itemp == 1) ? MAX_FILE_SIZE:ftell(fp)%MAX_FILE_SIZE;
		//printf("FileSize : %d\n",fileSize[noOfFiles]);
    if(readComplete){
      fclose(fp);fp = NULL;}
      noOfFiles++;
    
    noOfReads++;
  }

  if(eof == EOF && noOfReads ==0 ) break;
  //DEBUG: prints file
  /*temp = fileArray;itemp =0;
  while(itemp<noOfFiles){
//    printf("\n%s\n",temp);
	itemp++;
    temp+=200;
  }*/

  cudaMemset(dlock,0,MAX_HASH_ENTRIES*sizeof(int));
  if(redArea == 0){
  HANDLE_ERROR( cudaMemcpyAsync(dfileArray,fileArray,10*MAX_FILE_SIZE*sizeof(char),cudaMemcpyHostToDevice,stream) );
  HANDLE_ERROR( cudaMemcpyAsync(dfileSize, fileSize, 10*sizeof(int),               cudaMemcpyHostToDevice,stream) );
  HANDLE_ERROR( cudaStreamSynchronize( stream ) );
  getWordCounts<<<1,noOfFiles,0,stream>>>(dfileArray,dcountArray,dfileSize,dhashtable,dnextPtr, dlock);}
  else{
    //printf("\nRedArea 2 of GPU ");
  HANDLE_ERROR( cudaMemcpyAsync(dfileArray1,fileArray,10*MAX_FILE_SIZE*sizeof(char),cudaMemcpyHostToDevice,stream2) );
  HANDLE_ERROR( cudaMemcpyAsync(dfileSize1,fileSize,10*sizeof(int),cudaMemcpyHostToDevice,stream2) );
  HANDLE_ERROR( cudaStreamSynchronize( stream2 ) );
  getWordCounts<<<1,noOfFiles,0,stream2>>>(dfileArray1,dcountArray,dfileSize1,dhashtable,dnextPtr, dlock);
  }
  
   // printf("\nChecking if CPU BUSYY ...last pricess by GPU = %s..readComplete = %d",filename,readComplete);
  //Keeping CPU busy
  
  if((cpu==0||pthread_kill(cpu,0)!=0)&&(eof=scanf("%s",filename))!=EOF){//CPU is not already processing
  //  printf("\nCreating CPU thread...%s",filename);
    strcpy(filenameCPU,filename);
    create_thread();
  }


  redArea = (redArea==0) ? 1:0;
  if(noOfReads == BAGSIZE) noOfReads =0 ;
  else break;
  if(eof == EOF) break;
}//while (1)Q
  cudaStreamSynchronize(stream);
  cudaStreamSynchronize(stream2);
  cudaThreadSynchronize();
  cudaMemcpy(countArray,dcountArray,200*sizeof(int),cudaMemcpyDeviceToHost);
  cudaMemcpy(hashtable,dhashtable,20*200*sizeof(char),cudaMemcpyDeviceToHost);
  cudaMemcpy(nextPtr,dnextPtr,200*sizeof(int),cudaMemcpyDeviceToHost);

  if(cpu!=0&&pthread_kill(cpu,0)!=0)//CPU is not already processing
  pthread_join(cpu,NULL);
  
  gettimeofday(&tempo2, NULL);

 // launch a kernel with a single thread to greet from the device
  cudaPrintfDisplay();

  // clean up after cuPrintf
  cudaPrintfEnd();


  /*cnode *ptr;ptr = highest;
	while(ptr!=NULL){	
		 find hash of cnode->word  * 20]
		locate the actual location of word
		increment count
	}
 */
  //max holds hashvalue
  //displayCount();
  cnode_ptr = highest;
//  printf("\n-----word = %s\n",cnode_ptr->word);
  while(cnode_ptr!=NULL){itemp =0 ;max =0 ;
//	printf("\nChecing for  %s --1",cnode_ptr->word);
    while(cnode_ptr->word[itemp]) //calculate hash
    {	
	max+=cnode_ptr->word[itemp];
	itemp++;
    }
//	printf("\n--2");
    itemp2 =  max%M;
//    printf("\nTrying %d: %s %s",itemp2,cnode_ptr->word,&hashtable[itemp2*20]);
    while(itemp2!=-1&&strcmp(cnode_ptr->word,&hashtable[itemp2*20])!=0){ //find in table
//	printf("\ninstead %dfound :%s",itemp2,&hashtable[itemp2*20]);
	itemp2 = nextPtr[itemp2];
    }
	//printf("\n--3");
    if(itemp2!=-1) countArray[itemp2]+=cnode_ptr->count; //increment count since entry founs
    else {//not found
	itemp2 = M;
	//printf("\nDintf find  %s ",cnode_ptr->word);
	while(itemp2<MAX_HASH_ENTRIES && hashtable[itemp2*20]!='\0') itemp2++;
	if(itemp2==MAX_HASH_ENTRIES)//no place in hash table
      	  printf("%s:[%d]\n",cnode_ptr->word,cnode_ptr->count);
    }
    cnode_ptr = cnode_ptr->succ;
  }

  itemp=itemp2=0;max=-99,maxind = 0;
//  printf("\nNo Of Words : \n");
  for(itemp=0;itemp<200;itemp++){
	for(itemp2=0;itemp2<200;itemp2++)
	    if(hashtable[itemp2*20]!='\0'&&countArray[itemp2]!=0)
		if(countArray[itemp2] > max){
		  max = countArray[itemp2];
		  maxind = itemp2;
		}
	if(max!=-99){
      printf("%s:[%d]\n",&hashtable[maxind*20],max);
	max =-99; countArray[maxind] =0;
	}
	else break;
  }
elapsed_sec = (tempo2.tv_sec - tempo1.tv_sec)*1000+(tempo2.tv_usec - tempo1.tv_usec)/1000;
printf("Elapsed Time : %ld msec\n",elapsed_sec);		
//  itemp =0;
/*  while(itemp<200){
//    printf("\t%d",countArray[itemp]);itemp++;
    if(hashtable[itemp*20]!='\0'){
      printf("%d: %s:[%d]\n",itemp,&hashtable[itemp*20],countArray[itemp]);
    }
    itemp++;
  }*/
  cudaFree(dfileArray);
  cudaFree(dfileArray1);
  cudaFree(dcountArray);
  cudaFree(dhashtable);
  cudaFreeHost(fileArray);
  cudaFreeHost(fileSize);
  free(countArray);
  free(hashtable);
}
