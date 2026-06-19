# Salesforce Agent Rule

Workspace Rule do Google Antigravity para este repositorio Salesforce.

Use `AGENTS.md` como fonte principal de regras.

Nao duplique aqui o conteudo do `AGENTS.md`.

## Validacao obrigatoria de Work

Antes de qualquer implementacao que siga o fluxo de Work, valide a Work na org Elera usando apenas:

```powershell
scripts/check-work.ps1 "<WORK_NORMALIZADA>"
```

ou:

```bash
scripts/check-work.sh "<WORK_NORMALIZADA>"
```

O formato esperado e `W-xxxxxx`.

- `FOUND`: continue.
- `NOT_FOUND`: pare.
- `INVALID_WORK`: peca uma Work valida no formato `W-xxxxxx`.
- `AUTH_ERROR`: pare e oriente a configurar a autenticacao `elera-work-check`.

Nao consulte a Work manualmente via SOQL fora desses scripts, salvo manutencao da propria integracao.

Nao solicite nem registre senha, token, refresh token, client secret, certificado real ou chave privada. Arquivos JWT reais devem ficar fora do repositorio e de pacotes portateis.

## Economia de tokens

Ao iniciar chat novo, leia uma unica vez os arquivos relevantes e informe:

"Contexto carregado nesta conversa. Nao vou reler os mesmos arquivos nesta thread, salvo alteracao, solicitacao explicita ou necessidade real."

Na mesma thread, nao releia os mesmos arquivos sem necessidade.

## Regras especificas do Antigravity

- Antes de alterar qualquer arquivo, siga `AGENTS.md`.
- Consulte contexto especifico apenas quando a tarefa exigir.
- Nao explore alternativas fora do escopo.
- Nao proponha melhorias nao solicitadas.
- Nao altere codigo funcional nao relacionado.
- Nao gere scripts auxiliares sem solicitacao explicita.
- Nao execute comandos destrutivos.
- Nao faca commit.
- Nao faca push.
- Nao faca deploy.
- Nunca fazer deploy do `package.xml` inteiro.
- Deploy Salesforce deve ser granular por componente alterado ou criado.
- Nao deixe arquivos temporarios no projeto.
- Responder no formato definido no `AGENTS.md`.
