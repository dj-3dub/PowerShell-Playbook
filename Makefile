# ---- PowerShell-Automation-Toolkit Makefile ----
# Quick refs:
#   make identity           # Inactive AD + Password expiry (preview)
#   make security           # CA + Exchange hygiene + Local Admins + Defender status
#   make ops                # Support bundle + Cert expiry
#   make all-reports        # identity + security + ops (mock-friendly)
#   make run-inactive       # Inactive AD (Days=120 default)
#   make run-expiry         # Password expiry notices (preview)
#   make ca                 # Conditional Access report (mock on Linux)
#   make exo                # Exchange hygiene report (mock on Linux)
#   make local-admins       # Local admin report
#   make defender           # Defender status report (Windows only)
#   make certs              # Certificate expiry
#   make support            # Support bundle (zips to ./reports)
#   make serve              # Serve ./reports on http://<host>:PORT
#   make test               # Run full Pester suite
#   make clean-*            # Clean artifacts
#
# Vars you can override:
#   DAYS_INACTIVE=120 DAYS_EXPIRY=14 PORT=8080 REPORTS=./reports OUT=./out ENV=Dev

PWSH ?= pwsh
REPORTS ?= ./reports
OUT ?= ./out
ENV ?= Dev
DAYS_INACTIVE ?= 120
DAYS_EXPIRY ?= 14
PORT ?= 8080

define PWSH_RUN
$(PWSH) -NoProfile -Command "Import-Module ./src/EnterpriseOpsToolkit.psd1 -Force; $1"
endef

.PHONY: help identity security ops all-reports \
        run-inactive run-expiry ca exo local-admins defender certs support \
        test serve clean-out clean-reports

help:
	@sed -n '1,80p' Makefile | sed -n '1,50p' | sed -n '1,80p' >/dev/null || true
	@echo "See header comments for common targets and vars."

# --- Identity (new scripts you added) ---
identity: run-inactive run-expiry

run-inactive:
	@mkdir -p $(REPORTS)
	$(call PWSH_RUN, Get-InactiveAdAccounts -DaysInactive $(DAYS_INACTIVE) -OutputPath '$(REPORTS)')

run-expiry:
	@mkdir -p $(OUT)
	$(call PWSH_RUN, Send-PasswordExpiryNotifications -Days $(DAYS_EXPIRY) -Preview -OutputPath '$(OUT)')

# --- Security (existing public commands) ---
security: ca exo local-admins defender

ca:
	@mkdir -p $(REPORTS)
	$(call PWSH_RUN, Get-ConditionalAccessReport -Environment $(ENV) -OutputPath '$(REPORTS)')

exo:
	@mkdir -p $(REPORTS)
	$(call PWSH_RUN, Get-ExchangeHygieneReport -Environment $(ENV) -OutputPath '$(REPORTS)')

local-admins:
	@mkdir -p $(REPORTS)
	$(call PWSH_RUN, Get-LocalAdminReport -OutputPath '$(REPORTS)')

defender:
	@mkdir -p $(REPORTS)
	# This may warn/skip on Linux (Windows Defender cmdlets not present)
	$(call PWSH_RUN, Get-DefenderStatus -OutputPath '$(REPORTS)')

# --- Ops / hygiene ---
ops: support certs

support:
	@mkdir -p $(REPORTS)
	$(call PWSH_RUN, Collect-SupportBundle -OutputPath '$(REPORTS)')

certs:
	@mkdir -p $(REPORTS)
	$(call PWSH_RUN, Get-CertificateExpiry -OutputPath '$(REPORTS)')

# --- Everything we can run safely on Linux ---
all-reports: identity security ops

# --- Test runner ---
test:
	$(PWSH) -NoProfile -ExecutionPolicy Bypass -File ./Run-Tests.ps1

# --- Static file server for reports ---
serve:
	@cd $(REPORTS) && python3 -m http.server $(PORT) --bind 0.0.0.0

# --- Cleanup ---
clean-out:
	@rm -rf $(OUT)

clean-reports:
	@rm -rf $(REPORTS)

SHELL := /usr/bin/pwsh

.PHONY: test lint

lint:
	@pwsh -NoProfile -ExecutionPolicy Bypass -Command "Invoke-ScriptAnalyzer -Path './src' -Recurse -Severity Warning -ReportSummary"

test: lint
	@pwsh -NoProfile -ExecutionPolicy Bypass -File ./Run-Tests.ps1

