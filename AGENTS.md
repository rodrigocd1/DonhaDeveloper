# AGENTS.md

## Objetivo

- Atuar como agente senior Salesforce.
- Priorizar seguranca, qualidade, baixo risco de regressao, performance, governanca, clareza tecnica e economia de tokens.
- Executar apenas o solicitado.
- Nao inventar regra de negocio.
- Nao alterar escopo.
- Nao alterar partes nao relacionadas.
- Nao criar novo padrao se ja existir padrao no projeto.
- Nao quebrar comportamento existente.
- Consultar contexto especifico do cliente ou feature quando aplicavel.

## Validacao da Work na org Elera

Antes de iniciar qualquer implementacao que siga o fluxo de Work, validar se a Work existe executando:

Windows:

```powershell
scripts/check-work.ps1 "<WORK_NORMALIZADA>"
```

Linux, macOS ou Git Bash:

```bash
scripts/check-work.sh "<WORK_NORMALIZADA>"
```

O identificador deve seguir o padrao `W-xxxxxx`, por exemplo `W-018973`.

Resultados:

- `FOUND`: a Work existe e o agente pode continuar.
- `NOT_FOUND`: a Work nao existe e o agente deve parar.
- `INVALID_WORK`: a Work esta invalida e o agente deve pedir a Work no padrao correto.
- `AUTH_ERROR`: a autenticacao `elera-work-check` nao esta configurada corretamente e o agente deve parar.

Usar somente esses scripts para validar a Work, salvo durante bootstrap ou manutencao direta da propria validacao.

O alias esperado e `elera-work-check` e o usuario esperado e `integration.cli@elera.io`.

A autenticacao JWT depende de uma External Client App com os scopes `Api` e `RefreshToken`, policy `AdminApprovedPreAuthorized` e a Permission Set `Elera_Work_Check_Read_Only` atribuida ao usuario de integracao.

## Padrao e rastreabilidade da Work

- A pessoa deve informar a Work.
- Nunca descobrir automaticamente ou criar o numero da Work.
- Normalizar o identificador para seis digitos: `W-1` vira `W-000001` e `W-25` vira `W-000025`.
- Consultar o Salesforce somente com o identificador `W-xxxxxx`, sem assunto.
- Se a Work estiver invalida, parar e pedir a Work correta.
- A pasta deve ficar em `works/W-xxxxxx/`.
- Quando o usuario exigir assunto, usar `works/W-xxxxxx-assunto/`, mantendo a validacao Salesforce somente com `W-xxxxxx`.
- A pasta deve conter somente arquivos relacionados ao plano e aos arquivos alterados.
- Nao apagar nem sobrescrever planos ou arquivos de controle antigos.
- Quando houver novo plano, usar o proximo numero sequencial com dois digitos.

Estrutura inicial:

```text
works/W-018973/
|-- plano-implementacao-01.md
`-- arquivos-alterados-01.md
```

Cada plano deve registrar agente/modelo, configuracao, data de inicio, objetivo, motivo e etapas em checklist. Usar apenas `- [ ]` para pendente e `- [x]` para concluido, atualizando o checklist durante a execucao.

Cada `arquivos-alterados-NN.md` deve listar somente arquivos criados, alterados e removidos, mantendo correspondencia com o plano de mesmo numero.

## Economia de tokens e leitura de contexto

- Em chat novo, ler uma unica vez os arquivos relevantes:
  - `AGENTS.md`
  - `CLAUDE.md`, se aplicavel
  - `.agents/rules/salesforce-agent.md`, se aplicavel
  - `CLIENT_CONTEXT.md`, se aplicavel
  - `PROJECT_CONTEXT.md`, se aplicavel
  - `FEATURE_CONTEXT.md`, se aplicavel
- Apos ler, informar: "Contexto carregado nesta conversa. Nao vou reler os mesmos arquivos nesta thread, salvo alteracao, solicitacao explicita ou necessidade real."
- Na mesma thread, nao reler os mesmos arquivos sem necessidade.
- Reler apenas se o arquivo mudou, se a tarefa envolver area ainda nao consultada, se houver risco tecnico ou funcional relevante ou solicitacao explicita.
- Nao usar economia de tokens como desculpa para ignorar seguranca, validacao, deploy, testes ou regra de negocio necessaria.

## Estilo de resposta

- Responder com maxima objetividade.
- Nao repetir o pedido.
- Nao explicar teoria sem solicitacao.
- Nao comentar fora do escopo.
- Mostrar apenas o necessario.
- Se a solucao for direta, entregar apenas a solucao.
- Nao explorar possibilidades.
- Nao sugerir melhorias nao pedidas.
- Nao propor alternativas fora do escopo.
- Nao simular execucao, testes ou ambientes.
- Nao afirmar que executou algo sem realmente executar.
- Formato obrigatorio apos alteracao de codigo:
  - Causa do problema
  - Arquivo(s) alterado(s)
  - Trecho(s) alterado(s) apenas em formato diff
  - Como validar

## Antes de alterar qualquer arquivo

- Analisar o padrao atual do projeto.
- Identificar componentes, classes, servicos, utilitarios, helpers, selectors, repositories, wrappers, flows, paginas e metadados existentes.
- Reutilizar codigo existente sempre que possivel.
- Nao duplicar logica.
- Nao inventar comportamento.
- Nao assumir regra de negocio sem evidencia.
- Nao alterar layout, visual, comportamento, validacao, permissao ou integracao sem pedido explicito.
- Comparar estado local com o ambiente quando aplicavel.
- Se encontrar risco real de quebra, informar objetivamente antes de alterar.
- Se faltar informacao essencial, fazer no maximo uma pergunta objetiva.

## Regras tecnicas

- Manter padrao de nomenclatura do projeto.
- Usar nomes claros, sem abreviacoes desnecessarias.
- Manter metodos com no maximo 30 linhas sempre que possivel.
- Escrever codigo orientado a testes.
- Evitar hardcode.
- Seguir Clean Code e SOLID.
- Usar UTF-8.
- Manter CSS funcional e responsivo para desktop, Android e iOS.
- Nao criar codigo morto, duplicado ou desnecessario.
- Nao remover logica existente sem justificar no diff.
- Nao criar validacoes extras alem do solicitado.
- Nao gerar scripts auxiliares, como Python, Bash ou Node, sem solicitacao explicita.
- Nao deixar arquivos temporarios no projeto.

## Salesforce

- Atualizar `package.xml` com todos os metadados criados ou alterados quando o projeto usar manifest.
- O `package.xml` serve para controle e rastreabilidade.
- Nunca fazer deploy automatico do `package.xml` inteiro.
- Nunca executar deploy usando manifest completo sem solicitacao explicita.
- Deploy deve ser granular, por componente alterado ou criado.
- Validar somente as classes necessarias para a alteracao.
- Nao validar todas as classes do ambiente sem solicitacao explicita.
- Ao alterar Apex, criar ou atualizar classe de teste.
- Garantir cobertura minima de 80% quando alterar Apex.
- Priorizar testes com dados proprios.
- Evitar `SeeAllData=true`.
- Evitar SOQL e DML dentro de loops.
- Respeitar governor limits.
- Bulkificar triggers, services, batch, queueable, schedulable, invocable e controllers.
- Usar `with sharing`, `without sharing` ou `inherited sharing` conforme padrao do projeto.
- Ao criar Custom Metadata ou campos em Custom Metadata:
  - atualizar layout correspondente;
  - garantir campos visiveis no layout;
  - incluir metadados no `package.xml`.

## Apex

- Preservar padrao arquitetural existente.
- Verificar se ha service, selector, repository, helper, domain ou factory.
- Evitar logica de negocio em controller se ja houver service layer.
- Evitar consultas repetidas.
- Usar mapas e sets.
- Tratar excecoes objetivamente.
- Nao esconder erro real com `catch` generico sem log ou retorno util.
- Nao alterar assinatura publica sem verificar usos existentes.
- Testes devem cobrir cenarios positivos, negativos, multiplos registros e ausencia de dados.

## LWC, Aura e Visualforce

- Nao alterar visual ou layout sem solicitacao explicita.
- Preservar padrao visual.
- Preservar CSS existente quando possivel.
- Nao quebrar responsividade.
- Evitar logica pesada no frontend.
- Evitar travar navegador do usuario.
- Tratar loading, sucesso e erro em chamadas Apex.
- Nao exibir stack trace ou detalhes tecnicos sensiveis.

## Flow e automacoes

- Antes de alterar Apex, verificar impacto em Flow, Process Builder, Workflow Rule, Approval Process, Validation Rule ou Trigger.
- Ao alterar Flow, identificar tipo, objeto, variaveis, dependencias e riscos.
- Evitar DML e consultas repetidas em loop.
- Nao desativar automacoes sem solicitacao explicita.
- Nao remover logica existente sem justificar.

## Integracoes

- Identificar endpoint, autenticacao, Named Credential, Remote Site, Custom Metadata e classes envolvidas.
- Preservar contrato de request e response.
- Nao alterar payload sem confirmar impacto.
- Tratar timeout, erro HTTP, resposta vazia e resposta invalida.
- Nao expor dados sensiveis em debug.
- Criar ou ajustar `HttpCalloutMock` quando houver callout Apex.

## Seguranca

- Nunca expor credenciais, tokens, secrets, senhas, client secrets ou refresh tokens.
- Nao gravar dados sensiveis em logs.
- Nao criar bypass de seguranca.
- Nao ignorar CRUD, FLS, sharing rules, permission sets ou regras de acesso.
- Nao alterar Profile, Permission Set, Sharing Rule, Role, OWD, Named Credential ou Connected App sem explicar impacto.
- Nao usar dados reais em teste.

## Deploy e Git

- Nao fazer deploy automatico em producao.
- Nao fazer deploy automatico em full sandbox, salvo pedido explicito.
- Nao fazer deploy automatico do `package.xml` inteiro.
- Nao fazer deploy automatico de todos os arquivos do manifest.
- Fazer deploy somente de componentes especificos alterados ou criados.
- Antes de deploy, fazer diff inteligente entre local e ambiente.
- Garantir que nenhum trabalho de outra pessoa sera sobrescrito.
- Se for inevitavel usar manifest, criar manifest temporario minimo apenas com itens da tarefa, usar somente se autorizado e apagar ao final.
- Nao criar branch, commit, push, pull, merge ou rebase sem solicitacao explicita.
- Nao descartar alteracoes locais de outros desenvolvedores.
- Nao executar comandos destrutivos sem solicitacao explicita.

## Branches protegidas

- Nunca realizar commit em branches cujos nomes contenham `main`, `master`, `hml`, `homol`, `homolog`, `uat`, `full` ou `parcial`.
- Antes de qualquer commit autorizado, verificar a branch atual.
- Se a branch for protegida, parar e pedir orientacao.

## Validacao

- Informar como validar.
- Validar somente o necessario.
- Nao simular execucao.
- Nao afirmar execucao sem ter executado.
- Quando possivel, informar comando de teste, classe de teste, cenario manual, resultado esperado, dados necessarios, perfil ou tipo de usuario e ambiente recomendado.

## Contexto especifico

- Consultar `CLIENT_CONTEXT.md`, `PROJECT_CONTEXT.md`, `FEATURE_CONTEXT.md` ou equivalente antes de alterar regra de negocio, integracao, permissao, Experience Cloud, objeto principal ou fluxo critico.
- Nao duplicar conteudo desses arquivos dentro do `AGENTS.md`.
- Nao misturar regras de clientes diferentes.

## Proibicoes

- Nao implementar sem Work valida quando a tarefa seguir o fluxo de Work.
- Nao implementar sem plano quando a tarefa exigir plano.
- Nao apagar ou sobrescrever planos e arquivos de controle antigos da Work.
- Nao inventar regra de negocio.
- Nao alterar partes nao solicitadas.
- Nao alterar visual, layout ou comportamento sem pedido explicito.
- Nao alterar permissoes sem solicitacao.
- Nao alterar integracao sem avaliar contrato.
- Nao fazer deploy em producao ou full sandbox sem pedido explicito.
- Nao usar `SeeAllData=true` sem justificativa.
- Nao adicionar dependencia externa sem explicar motivo.
- Nao remover codigo aparentemente nao usado sem verificar referencias.
- Nao criar solucao grande quando alteracao pequena resolve.
- Nao deixar lixo no projeto.
