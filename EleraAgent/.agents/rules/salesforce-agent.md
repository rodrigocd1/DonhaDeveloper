# Salesforce Agent Rules

## Validacao obrigatoria de Work

Antes de qualquer implementacao, valide a Work na org Elera usando apenas:

```powershell
scripts/check-work.ps1 "<WORK_NORMALIZADA>"
```

ou:

```bash
scripts/check-work.sh "<WORK_NORMALIZADA>"
```

O formato esperado e `W-xxxxxx`.

Interprete os retornos assim:

- `FOUND`: continue.
- `NOT_FOUND`: pare.
- `INVALID_WORK`: peça uma Work valida no formato `W-xxxxxx`.
- `AUTH_ERROR`: pare e oriente a configurar a autenticacao `elera-work-check`.

Nao consulte a Work manualmente via SOQL fora desses scripts, salvo manutencao da propria integracao.

Nao solicite nem registre senha, token, refresh token, client secret, certificado real ou chave privada.

Arquivos JWT reais devem ficar fora do repositorio e fora de pacotes portateis.
