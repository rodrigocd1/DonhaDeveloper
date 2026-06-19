# Dependencias da validacao de Work

## Incluido no pacote

- `AGENTS.md`
- `CLAUDE.md`
- `.agents/rules/salesforce-agent.md`
- `scripts/check-work.ps1`
- `scripts/check-work.sh`
- `scripts/auth-elera-work-check.ps1`
- `scripts/auth-elera-work-check.sh`
- `scripts/setup-elera-work-check-env.ps1`
- `scripts/verify-elera-work-validation.ps1`
- `scripts/verify-elera-work-validation.sh`
- `docs/elera-work-check-setup.md`
- `.env.example`
- `.gitignore`
- `.vscode/tasks.json`
- `PORTABLE-INSTALL.md`
- `DEPENDENCIES.md`

## Necessario no ambiente destino

- Salesforce CLI (`sf`) instalado e disponivel no PATH.
- Windows PowerShell para scripts `.ps1`.
- Bash e Node.js para scripts `.sh`.
- Variaveis `SF_ELERA_USERNAME`, `SF_ELERA_CLIENT_ID`, `SF_ELERA_JWT_KEY_FILE` e `SF_ELERA_INSTANCE_URL`.
- Alias `elera-work-check` autenticado, ou variaveis JWT prontas para autenticar.
- Usuario `integration.cli@elera.io` com permissao minima para API e leitura de `agf__ADM_Work__c.Name`.
- Chave privada JWT local fora do projeto, apontada por `SF_ELERA_JWT_KEY_FILE`.
- Certificado publico correspondente carregado na External Client App da org Elera.

## Verificacao segura

Windows:

```powershell
scripts/verify-elera-work-validation.ps1 "W-018973"
```

Linux, macOS ou Git Bash:

```bash
scripts/verify-elera-work-validation.sh "W-018973"
```

Esses scripts verificam os componentes locais sem abrir nem imprimir a chave privada.

## Itens que ficam fora do pacote

- `.key`, `.pem`, `.p12` ou `.jks` reais.
- `.env` real.
- `.sf/` ou `.sfdx/`.
- `node_modules/`.
- Senhas, tokens, refresh tokens, client secrets ou chaves privadas.

Esses itens devem ser configurados localmente fora do repositorio.
