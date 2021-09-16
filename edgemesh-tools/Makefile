BDIR=./bin

all: noproxy select

noproxy: ./noproxy/noproxy.go
	go build -o $(BDIR)/noproxy $^

select: ./select/select.go
	go build -o $(BDIR)/select $^

.PHONY: clean
clean:
	rm -rf $(BDIR)/*
