format:
	stylua -v --verify .

lint:
	luacheck lua/

test:
	./scripts/run_tests.sh
