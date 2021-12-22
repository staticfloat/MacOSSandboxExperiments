all: test

build:
	mkdir -p $@

build/access_test: access_test.c | build
	$(CC) -o $@ $<

build/access_test.sb: access_test.sb.template | build
	PWD=$(shell pwd) envsubst '$${PWD}' < $< > $@

test: build/access_test build/access_test.sb
	sandbox-exec -f ./build/access_test.sb ./build/access_test

clean:
	rm -rf build
