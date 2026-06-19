# Claude Code

Use `AGENTS.md` como fonte principal de regras.

Nao duplique regras operacionais neste arquivo.

## Economia de tokens

No inicio de uma conversa nova, carregue uma unica vez o contexto necessario e informe:

"Contexto carregado nesta conversa. Nao vou reler os mesmos arquivos nesta thread, salvo alteracao, solicitacao explicita ou necessidade real."

Na mesma thread, nao releia arquivos ja carregados sem necessidade.

## Regras especificas do Claude

- Antes de alteracoes relevantes, apresente plano objetivo apenas quando houver risco tecnico real.
- Nao use plano longo para alteracao simples.
- Nao explore alternativas fora do escopo.
- Nao execute comandos destrutivos.
- Nao faca commit.
- Nao faca deploy.
- Nao rode deploy do `package.xml` inteiro.
- Para deploy Salesforce, sugerir apenas deploy granular por componente alterado/criado.
- Consultar `CLIENT_CONTEXT.md`, `PROJECT_CONTEXT.md` ou `FEATURE_CONTEXT.md` quando a tarefa envolver regra de negocio, integracao, permissao, Experience Cloud, objeto principal ou fluxo critico.
- Responder de forma direta, tecnica e objetiva.
