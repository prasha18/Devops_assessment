.PHONY: help env deps clean lint test e2e security reports quality \
        agent-setup agent-resetdb agent-smoke agent-test

VENV_PYTHON=env/bin/python
REPORTS_DIR=reports
E2E_RESULTS_DIR=test-results
BASE_URL=http://127.0.0.1:4000

help:
	@echo "  env         create a development environment"
	@echo "  deps        install dependencies"
	@echo "  clean       remove unwanted files"
	@echo "  lint        run Ruff lint checks"
	@echo "  test        run backend tests with JUnit and coverage"
	@echo "  e2e         run Playwright UI tests"
	@echo "  security    run Bandit security scan"
	@echo "  reports     generate static/security reports"
	@echo "  quality     run the complete quality pipeline"
	@echo "  agent-setup install dependencies in ./env"
	@echo "  agent-resetdb reset and seed local development database"
	@echo "  agent-smoke run fast smoke tests"
	@echo "  agent-test  run full test suite with coverage"

env:
	python3 -m venv env && \
	. env/bin/activate && \
	make deps

deps:
	$(VENV_PYTHON) -m pip install -r requirements.txt

clean:
	find . -type d -name "__pycache__" -prune -exec rm -rf {} +
	find . -type f \( -name "*.pyc" -o -name "*.pyo" -o -name ".DS_Store" \) -delete

reports-dir:
	mkdir -p $(REPORTS_DIR)

$(E2E_RESULTS_DIR):
	mkdir -p $(E2E_RESULTS_DIR)

lint: reports-dir
	$(VENV_PYTHON) -m ruff check appname tests --output-format=json > $(REPORTS_DIR)/ruff.json
	$(VENV_PYTHON) -m ruff check appname tests

test: reports-dir
	APPNAME_ENV=test $(VENV_PYTHON) -m pytest tests --ignore=tests/e2e \
		--junitxml=$(REPORTS_DIR)/junit.xml \
		--cov=appname \
		--cov-report=term-missing \
		--cov-report=xml:$(REPORTS_DIR)/coverage.xml \
		--cov-report=html:$(REPORTS_DIR)/coverage-html

e2e: $(E2E_RESULTS_DIR)
	@echo "Resetting development database..."
	APPNAME_ENV=dev $(VENV_PYTHON) manage.py resetdb
	@echo "Starting Flask application..."
	APPNAME_ENV=dev FLASK_APP=manage $(VENV_PYTHON) -m flask run --host=127.0.0.1 --port=4000 > $(E2E_RESULTS_DIR)/flask.log 2>&1 & echo $$! > $(E2E_RESULTS_DIR)/flask.pid
	@echo "Waiting for Flask application..."
	@for i in $$(seq 1 30); do \
		if curl -sf http://127.0.0.1:4000/login > /dev/null; then \
			echo "Flask application is ready."; \
			break; \
		fi; \
		sleep 1; \
	done
	@BASE_URL=$(BASE_URL) APPNAME_ENV=dev $(VENV_PYTHON) -m pytest tests/e2e \
		--browser chromium \
		--tracing retain-on-failure \
		--screenshot only-on-failure \
		--output=$(E2E_RESULTS_DIR) \
		--junitxml=$(E2E_RESULTS_DIR)/junit.xml; \
	status=$$?; \
	if [ -f $(E2E_RESULTS_DIR)/flask.pid ]; then kill $$(cat $(E2E_RESULTS_DIR)/flask.pid) || true; fi; \
	exit $$status

security: reports-dir
	$(VENV_PYTHON) -m bandit -r appname -f json -o $(REPORTS_DIR)/bandit.json
	$(VENV_PYTHON) -m bandit -r appname

reports: lint security

quality: reports test e2e

agent-setup:
	python3 -m venv env
	$(VENV_PYTHON) -m pip install --upgrade pip
	$(VENV_PYTHON) -m pip install -r requirements.txt

agent-resetdb:
	@if [ ! -x "$(VENV_PYTHON)" ]; then echo "Run 'make agent-setup' first."; exit 1; fi
	APPNAME_ENV=dev $(VENV_PYTHON) manage.py resetdb

agent-smoke:
	@if [ ! -x "$(VENV_PYTHON)" ]; then echo "Run 'make agent-setup' first."; exit 1; fi
	APPNAME_ENV=test $(VENV_PYTHON) -m pytest -q tests/test_urls.py tests/test_login.py

agent-test:
	@if [ ! -x "$(VENV_PYTHON)" ]; then echo "Run 'make agent-setup' first."; exit 1; fi
	APPNAME_ENV=test $(VENV_PYTHON) -m pytest tests --ignore=tests/e2e \
		--cov-report=term-missing \
		--cov=appname
