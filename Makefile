.PHONY: app build check test signing-check signing-identity clean

build:
	./Scripts/swift.sh build

test:
	./Scripts/swift.sh test

check:
	./Scripts/swift.sh run chimlo-check

app:
	./Scripts/package-app.sh

signing-identity:
	./Scripts/setup-local-signing.sh

signing-check: app
	./Scripts/check-stable-signing.sh

clean:
	swift package clean
