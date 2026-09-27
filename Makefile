# EyeRest developer shortcuts. `make install` is all most people need.

.PHONY: build test app run install clean

# Debug build of every target.
build:
	swift build

# Run the unit tests (Swift Testing; no Xcode needed).
test:
	swift test

# Build, bundle and ad-hoc sign build/EyeRest.app.
app:
	scripts/build-app.sh

# Build the app, quit any running copy and open the fresh build.
run:
	scripts/build-app.sh --open

# Build, install to ~/Applications and open it.
install:
	scripts/build-app.sh --install --open

# Remove SwiftPM and app build products.
clean:
	rm -rf .build build
