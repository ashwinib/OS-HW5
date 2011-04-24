all: p3 

p3: p3.cu
	nvcc -o p3 p3.cu -arch sm_11 -w

p4: p4.c
	gcc -o p4 p4.c -lpthread -lrt

p4w: p4-working.c
	gcc -o p4w p4-working.c -lpthread
clean:
	rm p3
