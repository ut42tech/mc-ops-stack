.PHONY: secret setup up down logs restart ps

## Generate the shared forwarding + RCON secrets (single source of truth). Run once.
secret:
	@mkdir -p secrets
	@for f in forwarding.secret rcon.secret; do \
		if [ -s secrets/$$f ]; then \
			echo "secrets/$$f already exists; leaving it untouched."; \
		else \
			openssl rand -hex 24 > secrets/$$f; \
			echo "Wrote secrets/$$f"; \
		fi; \
	done

## Materialize .env from the committed .env.example template (kept if it exists).
setup:
	@[ -f .env ] || { cp .env.example .env; echo "Created .env"; }

up:
	docker compose up -d

down:
	docker compose down

restart:
	docker compose restart

ps:
	docker compose ps

logs:
	docker compose logs -f
