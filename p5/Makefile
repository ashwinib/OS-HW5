all: p3 

p3: p3.cu
	nvcc -o p3 p3.cu -arch sm_11 -w

p4: p4.c
	gcc -o p4 p4.c -lpthread -lrt

p4w: p4-working.c
	gcc -o p4w p4-working.c -lpthread

p5cpu.o: p5cpu.c p5cpu.h
	gcc -c p5cpu.c -lpthread

p5.o: p5.cu p5cpu.h
	nvcc -c p5.cu -arch sm_11 -w 

p5: p5.o p5cpu.o
	nvcc -o p5 p5.o p5cpu.o -lpthread  

clean:
	rm p3 p5 *.o
