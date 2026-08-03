# Compiles to shared library for R

CC = R CMD SHLIB
SRC = src/dcf_kernel.c
OUT = src/dcf_kernel.so

all: $(OUT)

$(OUT): $(SRC)
	$(CC) $(SRC) -o $(OUT)

clean:
	rm -f src/*.so src/*.o