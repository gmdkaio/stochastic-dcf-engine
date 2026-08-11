# Compiles to shared library for R

CC = R CMD SHLIB
SRC = src/dcf_kernel.c
DYNLIB_EXT := $(shell Rscript -e "cat(.Platform$$dynlib.ext)")
OUT = src/dcf_kernel$(DYNLIB_EXT)

all: $(OUT)

$(OUT): $(SRC)
	$(CC) $(SRC) -o $(OUT)

clean:
	rm -f src/*.so src/*.dll src/*.o