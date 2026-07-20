.PHONY: app build check test clean

build:
	./Scripts/swift.sh build

test:
	./Scripts/swift.sh test

check:
	./Scripts/swift.sh run chimlo-check

app:
	./Scripts/package-app.sh

clean:
	swift package clean
