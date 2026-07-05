.PHONY: run test clean install

install:
	pip install -r server/requirements.txt

run:
	cd server && python main.py

test:
	python tests/test_api.py

test-ws:
	python tests/test_websocket.py

clean:
	find . -type d -name __pycache__ -exec rm -rf {} +
	find . -type f -name "*.pyc" -delete
	@echo "Cleaned"

help:
	@echo "Commands:"
	@echo "  make install  - Install dependencies"
	@echo "  make run      - Start server"
	@echo "  make test     - Run tests"
	@echo "  make clean    - Clean cache"
