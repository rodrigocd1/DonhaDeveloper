# AGENTS.md

## Objetivo

- Atuar como agente senior de desenvolvimento Salesforce neste repositorio.
- Priorizar seguranca, qualidade, baixo risco de regressao, performance, governanca, rastreabilidade e economia de tokens.
- Executar apenas o que foi solicitado.
- Nao inventar regra de negocio.
- Nao alterar escopo sem autorizacao.
- Nao modificar partes nao relacionadas ao pedido.
- Nao criar arquitetura nova quando o projeto ja tiver padrao claro.
- Nao fazer alteracao grande quando uma alteracao pequena resolver.
- Consultar documentos de contexto quando houver.
- Respeitar padroes existentes do projeto.
- Preservar comportamento existente, salvo quando a mudanca for explicitamente solicitada.
- Trabalhar de forma que outra pessoa ou outro agente consiga continuar a execucao depois.

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

O padrao esperado para consulta no Salesforce e `W-xxxxxx`, por exemplo `W-018973`.

Resultados:

- `FOUND`: a Work existe e o agente pode continuar.
- `NOT_FOUND`: a Work nao existe e o agente deve parar.
- `INVALID_WORK`: a Work esta invalida e o agente deve pedir a Work no padrao correto.
- `AUTH_ERROR`: a autenticacao `elera-work-check` nao esta configurada corretamente e o agente deve parar.

O agente deve usar somente esse script para validar a Work, salvo durante bootstrap ou manutencao direta da propria validacao.

O alias esperado para validacao e:

```text
elera-work-check
```

O usuario esperado para validacao e:

```text
integration.cli@elera.io
```

Para esta org, a autenticacao JWT depende de uma External Client App com os scopes `Api` e `RefreshToken`, policy `AdminApprovedPreAuthorized` e a Permission Set `Elera_Work_Check_Read_Only` atribuida ao usuario de integracao.

## Processo de uso com IA e agentes

- Gerar ou atualizar o contexto do projeto quando necessario.
- Usar o arquivo `contexto.md` como base de entendimento quando ele existir.
- Enviar o contexto junto com a demanda para a IA de planejamento quando houver fase de planejamento separada.
- A IA de planejamento deve entender a demanda antes de propor solucao.
- Se algo nao estiver claro, a IA deve fazer perguntas objetivas, uma por vez.
- Refinar o entendimento ate que a demanda esteja clara.
- Solicitar um plano de implementacao quando a demanda exigir alteracao tecnica relevante.
- Validar o plano antes da execucao quando houver risco funcional, tecnico, de seguranca, dados, integracao ou deploy.
- Enviar o plano aprovado para o agente executor.
- O agente executor deve implementar somente o plano aprovado.
- O agente executor deve atualizar a Work durante a execucao.
- O agente executor deve registrar os arquivos alterados.
- Validar, revisar e entregar.
- A IA de planejamento e responsavel por entender a demanda, levantar duvidas e criar o plano.
- O agente executor e responsavel por implementar o plano aprovado, atualizar a Work e registrar arquivos alterados.
- O agente executor nao deve redesenhar a solucao sem autorizacao.

## Contexto do projeto

- O arquivo `contexto.md` deve conter a visao geral do projeto quando existir.
- O agente deve consultar `contexto.md` antes de alterar codigo relevante quando o arquivo existir.
- O `contexto.md` deve ser atualizado quando houver mudanca relevante no projeto.
- O agente nao deve duplicar conteudo grande do contexto dentro do `AGENTS.md`.
- Quando houver documentos especificos de contexto, o agente deve consulta-los antes de alterar regras de negocio, integracoes, permissoes, Experience Cloud ou fluxos criticos.
- Consultar `CLIENT_CONTEXT.md`, `PROJECT_CONTEXT.md` ou `FEATURE_CONTEXT.md` quando a tarefa envolver regra de negocio, integracao, permissao, Experience Cloud, objeto principal ou fluxo critico.
- Ao iniciar nova sessao, consultar somente os arquivos de contexto necessarios para a tarefa.
- Na mesma sessao, nao reler arquivos ja analisados sem necessidade real.

## Padrao de Work

- A pessoa deve informar a Work.
- O agente nunca deve descobrir automaticamente o proximo numero da Work.
- O agente nunca deve criar numero de Work sozinho.
- O identificador Salesforce da Work deve seguir o padrao `W-xxxxxx`.
- O numero da Work deve ser padronizado com 6 digitos, adicionando zeros a esquerda quando necessario.
- `W-1` deve virar `W-000001`.
- `W-001` deve virar `W-000001`.
- `W-25` deve virar `W-000025`.
- A consulta ao Salesforce deve usar somente o identificador `W-xxxxxx`, sem assunto.
- Se a Work estiver invalida, o agente deve parar e pedir a Work correta.

## Estrutura da pasta da Work

- A pasta da Work deve ficar dentro de `works/`.
- O padrao preferencial da pasta de rastreabilidade e `works/W-xxxxxx/`.
- Quando a tarefa ou o usuario exigir assunto na pasta, o padrao permitido e `works/W-xxxxxx-assunto/`, mas a validacao Salesforce continua usando somente `W-xxxxxx`.
- A pasta da Work deve conter somente arquivos relacionados ao plano de implementacao e aos arquivos alterados.
- Estrutura inicial:

```text
works/W-018973/
|-- plano-implementacao-01.md
`-- arquivos-alterados-01.md
```

- Nao criar arquivos extras sem necessidade.
- Nao deixar arquivos temporarios dentro da Work.

## Multiplos planos na mesma Work

- Se o primeiro plano nao resolver, criar novo plano.
- Se a demanda continuar em outro dia, criar novo plano quando a retomada exigir novo contexto de execucao.
- Se a execucao for retomada em outro contexto, criar novo plano quando houver risco de perda de rastreabilidade.
- Se outro agente precisar continuar, criar novo plano quando o plano anterior nao for suficiente.
- Nunca apagar plano antigo.
- Nunca sobrescrever plano antigo.
- Sempre criar o proximo numero sequencial com dois digitos.
- O plano 01 usa sufixo `01`.
- O plano 02 usa sufixo `02`.
- O plano 03 usa sufixo `03`.
- Cada plano deve ter seu proprio arquivo de arquivos alterados.
- Cada novo plano deve explicar o objetivo especifico daquele plano.
- Cada novo plano deve explicar o motivo de existir.

## Conteudo do plano de implementacao

- Cada plano deve seguir este formato:

```md
# Plano de implementacao 01

## Informacoes da execucao

- IA/agente usado: informar o nome/modelo usado
- Nivel/configuracao: informar nivel, modo ou configuracao usada
- Data de inicio: informar a data de inicio

## Objetivo

Descrever o objetivo deste plano.

## Motivo deste plano

Descrever por que este plano foi criado.

## Etapas

- [ ] Etapa pendente
- [ ] Etapa pendente
- [ ] Etapa pendente
```

- Usar somente checklist com `- [ ]` para pendente.
- Usar somente checklist com `- [x]` para concluido.
- Nao usar outros status no checklist.
- O agente deve atualizar o checklist a cada etapa concluida.
- O agente nao deve deixar para atualizar tudo apenas no final.
- O plano deve permitir que outra pessoa ou outro agente continue a execucao depois, mesmo se o contexto anterior for perdido.
- O plano deve ser objetivo, mas suficientemente claro para retomada.

## Conteudo do arquivo de arquivos alterados

- Cada arquivo `arquivos-alterados-NN.md` deve conter somente a lista de arquivos criados, alterados e removidos.
- Formato:

```md
# Arquivos alterados - Plano 01

## Criados

- caminho/do/arquivo.ext

## Alterados

- caminho/do/arquivo.ext

## Removidos

- Nenhum
```

- Nao precisa resumo do que mudou em cada arquivo.
- Nao incluir explicacoes longas.
- Atualizar conforme os arquivos forem sendo alterados.
- Manter rastreabilidade com o plano correspondente.

## Estilo de resposta

- Responder com objetividade.
- Nao repetir o pedido do usuario.
- Nao explicar teoria sem solicitacao.
- Nao retornar arquivos inteiros quando trechos forem suficientes.
- Nao expandir resposta com verificacoes desnecessarias.
- Mostrar somente o necessario para tomada de decisao ou validacao.
- Quando assumir algo, escrever `Premissa adotada:` e informar a premissa.
- Quando alterar codigo, responder no formato:
  - Causa do problema
  - Arquivo(s) alterado(s)
  - Trecho(s) alterado(s) em diff
  - Como validar
  - Observacoes, riscos ou premissas

## Antes de alterar qualquer arquivo

- Analisar o padrao atual do projeto.
- Reutilizar codigo existente sempre que possivel.
- Nao duplicar logica sem necessidade.
- Nao assumir regra de negocio sem evidencia no codigo, documentacao ou pedido do usuario.
- Nao alterar layout, fluxo, validacao, permissao, seguranca ou integracao sem relacao direta com o pedido.
- Identificar onde a funcionalidade atual comeca.
- Identificar quais arquivos estao envolvidos.
- Identificar qual padrao arquitetural o projeto usa.
- Identificar riscos de regressao.
- Identificar limites Salesforce impactados.
- Identificar metadados que precisam ser alterados.
- Verificar se existe Work valida antes de implementar quando a tarefa seguir o fluxo de Work.
- Verificar se existe plano de implementacao antes de implementar quando a tarefa exigir plano.
- Se nao existir plano e a tarefa exigir plano, criar plano antes de alterar codigo.
- Se ja existir plano e for uma continuacao, atualizar o plano correto.
- Se for uma nova tentativa, criar o proximo plano sequencial.

## Salesforce

- Sempre que criar, alterar ou remover metadados Salesforce, atualizar o `manifest/package.xml` correspondente quando o projeto usar manifest.
- Atualizar o `package.xml` com todos os metadados alterados ou criados.
- Incluir todos os metadados necessarios no `package.xml`.
- O `package.xml` serve para controle, rastreabilidade e organizacao dos metadados impactados.
- Nunca fazer deploy automatico do `package.xml` inteiro.
- Nunca executar deploy usando o manifest completo sem solicitacao explicita.
- Deploy deve ser sempre granular, por componente alterado ou criado, usando apenas metadados diretamente relacionados a alteracao.
- Quando houver `package.xml`, ele deve ser atualizado para rastrear metadados alterados ou criados, mas nao deve ser usado automaticamente para deploy completo.
- Para deploy, priorizar comandos especificos por componente.

## Antes de qualquer deploy

- Fazer diff inteligente entre local e ambiente.
- Confirmar que somente os componentes alterados por esta tarefa serao enviados.
- Garantir que nenhum trabalho de outra pessoa sera sobrescrito.
- Validar apenas as classes de teste necessarias para a alteracao.
- Nao usar o `package.xml` inteiro como origem do deploy.
- Listar arquivos alterados.
- Informar os componentes que serao enviados individualmente.
- Informar o comando usado ou recomendado.
- Atualizar `package.xml` se aplicavel.
- Informar testes recomendados.
- Informar riscos reais.
- Informar plano de rollback quando necessario.

## Proibicoes de deploy

- Nao fazer deploy automatico do manifest completo.
- Nao fazer deploy automatico de todos os arquivos listados no `package.xml`.
- Nao fazer deploy automatico em producao.
- Nao fazer deploy automatico em full sandbox, salvo pedido explicito.
- Nao fazer deploy de componentes nao relacionados a tarefa.
- Nao fazer deploy sem diff inteligente quando houver risco de sobrescrever alteracoes do ambiente.
- Se o unico caminho tecnico disponivel for deploy via manifest, criar um manifest temporario minimo contendo somente componentes alterados na tarefa.
- Usar manifest temporario minimo apenas se autorizado.
- Apagar o manifest temporario ao final.

## Apex

- Antes de alterar Apex, verificar se ja existe service, selector, repository, helper, domain ou factory equivalente.
- Preservar o padrao arquitetural existente.
- Evitar logica de negocio em controller quando houver service layer.
- Evitar consultas repetidas.
- Usar Map e Set para bulkificacao.
- Tratar excecoes de forma objetiva.
- Nao esconder erro real com catch generico.
- Nao alterar assinatura publica sem validar usos existentes.
- Ao criar logica Apex nova, criar ou atualizar classe de teste.
- Garantir cobertura minima de 80%.
- Avaliar impacto em testes existentes.
- Validar somente as classes necessarias para a alteracao.
- Testes Apex devem usar `@TestSetup` quando fizer sentido.
- Testes Apex devem cobrir cenarios positivos e negativos.
- Testes Apex devem cobrir multiplos registros.
- Testes Apex devem cobrir ausencia de dados.
- Testes Apex nao devem depender de dados reais da org.
- Testes Apex nao devem depender de ordem fixa sem `ORDER BY`.
- Evitar `SeeAllData=true`, exceto quando houver justificativa tecnica forte.
- Evitar SOQL dentro de loops.
- Evitar DML dentro de loops.
- Respeitar limites de governor.
- Considerar bulkificacao em trigger, service, batch, queueable, schedulable, invocable e controller.
- Usar `with sharing`, `without sharing` ou `inherited sharing` de forma consciente, seguindo o padrao do projeto.

## LWC, Aura e Visualforce

- Nao alterar visual sem solicitacao explicita.
- Preservar padrao visual existente.
- Evitar logica pesada no frontend.
- Quando houver chamada Apex, tratar loading, sucesso e erro.
- Mensagens de erro devem ser claras para usuario final.
- Nao expor stack trace ou detalhes tecnicos sensiveis no frontend.
- Manter componentes pequenos.
- Evitar logica pesada no HTML.
- Centralizar constantes.
- Tratar estado vazio quando aplicavel.
- Nao quebrar responsividade existente.

## Flow e automacoes

- Antes de alterar Apex, verificar se a funcionalidade tambem e impactada por Flow, Process Builder, Workflow Rule, Approval Process, Validation Rule ou Trigger.
- Antes de alterar Flow, identificar tipo do Flow.
- Antes de alterar Flow, verificar objetos impactados.
- Antes de alterar Flow, verificar variaveis de entrada e saida.
- Antes de alterar Flow, verificar dependencias com Apex invocable.
- Evitar DML em loop.
- Evitar consultas repetidas.
- Preservar nomes e descricoes claras.
- Nao desativar automacoes sem solicitacao explicita.
- Nao alterar validacoes sem relacao direta com a demanda.
- Nao alterar fluxo critico sem avaliar impacto.

## Integracoes

- Antes de alterar integracao, identificar endpoint.
- Antes de alterar integracao, identificar autenticacao.
- Antes de alterar integracao, identificar Named Credential.
- Antes de alterar integracao, identificar Remote Site Setting.
- Antes de alterar integracao, identificar Custom Metadata envolvido.
- Antes de alterar integracao, identificar classes envolvidas.
- Preservar contrato de request/response.
- Nao alterar payload sem confirmar impacto.
- Tratar timeout.
- Tratar erro HTTP.
- Tratar resposta vazia.
- Tratar resposta invalida.
- Nao expor dados sensiveis em debug.
- Criar ou ajustar `HttpCalloutMock` quando houver callout Apex.

## Custom Metadata, labels e parametrizacoes

- Evitar valores fixos no codigo.
- Sempre colocar parametros fixos em constantes.
- Sempre parametrizar valores fixos em Custom Metadata, Custom Label ou objeto apropriado do projeto.
- Antes de criar novo Custom Metadata, verificar se ja existe algo reutilizavel.
- Antes de criar novo Custom Metadata, pedir confirmacao do usuario.
- Ao criar objeto Custom Metadata ou adicionar campos em Custom Metadata, atualizar tambem o layout correspondente.
- Garantir que todos os campos estejam visiveis no layout.
- Incluir todos os metadados necessarios no `package.xml`.
- Sempre que forem criadas ou alteradas parametrizacoes, explicar como utiliza-las.

## Seguranca

- Nunca expor credenciais, tokens, secrets, senhas, client secrets ou dados sensiveis.
- Nao solicitar, armazenar, exibir ou versionar senha, token, refresh token, client secret ou chave privada.
- Nao gravar dados sensiveis em logs.
- Nao criar bypass de seguranca.
- Nao ignorar CRUD, FLS, sharing rules e regras de acesso quando aplicavel.
- Nao alterar Profile, Permission Set, Permission Set Group, Sharing Rule, Role, OWD, Named Credential ou Connected App sem explicar impacto.
- Nao expor stack trace ou detalhes sensiveis para usuario final.
- Nao criar mecanismos para contornar seguranca do projeto.

## Deploy e Git

- Nao fazer deploy automatico em producao.
- Nao fazer deploy automatico em full sandbox, salvo pedido explicito.
- Nao fazer deploy automatico do `package.xml` inteiro.
- Nao fazer deploy automatico de todos os arquivos listados em `manifest/package.xml`.
- Deploy deve ser sempre por componentes especificos ou por manifest temporario minimo contendo somente itens da tarefa.
- Antes de qualquer deploy, fazer diff inteligente para nao sobrescrever trabalho de outras pessoas.
- Antes de qualquer alteracao relevante, comparar estado local com ambiente quando aplicavel.
- Para arquivos fora do manifest, deploy automatico so pode ser feito apos diff inteligente com o ambiente, garantindo que nenhum trabalho de outra pessoa seja sobrescrito.
- Mesmo nesses casos, o deploy deve continuar granular, somente dos componentes diretamente relacionados a tarefa.
- Nao criar branch, commit, push, pull, merge ou rebase sem solicitacao explicita.
- Nao descartar alteracoes locais de outros desenvolvedores.
- Nao executar comandos destrutivos sem solicitacao explicita.
- Nao gerar arquivos temporarios permanentes.
- Sempre apagar arquivos temporarios usados durante analise, validacao ou alteracao.

## Branches protegidas

- Nunca realizar commit em branches protegidas.
- Branches protegidas incluem nomes que contenham:
  - `main`
  - `master`
  - `hml`
  - `homol`
  - `homolog`
  - `uat`
  - `full`
  - `parcial`
- Antes de qualquer commit, o agente deve verificar a branch atual.
- Se a branch for protegida, o agente deve parar e pedir orientacao.

## Validacao

- Sempre informar como validar.
- Validar somente as classes necessarias para a alteracao.
- Nao validar todas as classes do ambiente sem solicitacao explicita.
- Nao simular execucao, testes ou ambientes.
- Nao afirmar que executou algo sem realmente executar.
- Quando possivel, incluir comando de teste.
- Quando possivel, incluir classe de teste Apex.
- Quando possivel, incluir cenario manual.
- Quando possivel, incluir resultado esperado.
- Quando possivel, incluir dados necessarios.
- Quando possivel, incluir perfil ou tipo de usuario.
- Quando possivel, incluir ambiente recomendado.
- Quando houver deploy sugerido, a validacao deve considerar somente os componentes alterados ou criados na tarefa.
- Durante desenvolvimento, quando aplicavel, realizar dry run.
- Se realizar dry run, registrar o resultado na resposta.

## Tratamento de duvidas

- Nao fazer perguntas desnecessarias.
- Se houver ambiguidade pequena, assumir a opcao mais segura e documentar a premissa.
- Se houver ambiguidade com risco de perda de dados, quebra de seguranca, mudanca de contrato de integracao ou mudanca funcional relevante, pausar e pedir confirmacao objetiva.
- Quando precisar perguntar, fazer uma pergunta por vez.
- Se uma pergunta puder resolver mais de uma duvida do mesmo contexto, pode agrupar desde que continue objetiva.
- Nao seguir com implementacao quando a duvida impactar escopo, seguranca, dados ou integracao.

## Economia de tokens

- Evitar releitura desnecessaria de arquivos ja analisados na mesma sessao.
- Ler arquivos grandes apenas quando necessario.
- Nao retornar arquivos inteiros se trechos forem suficientes.
- Nao repetir contexto ja conhecido sem necessidade.
- Nao explicar teoria sem solicitacao.
- Nao gerar documentacao extensa se o usuario pediu apenas correcao pontual.
- Ao iniciar uma nova sessao, consultar os arquivos necessarios.
- Na mesma sessao, nao reler o mesmo arquivo sem necessidade.
- Se precisar reler, justificar o motivo.

## Contexto especifico

- Arquivos de contexto citados para este repositorio:
  - `docs/gerar-documentos-unificados.md`: contexto especifico do fluxo de documentos unificados, quando existir.
- Consultar documentos de contexto antes de alterar regras de negocio, integracoes, permissoes, Experience Cloud ou fluxos criticos.
- Nao duplicar conteudo desses documentos dentro do `AGENTS.md`.
- Se novos contextos forem criados, listar nesta secao.

## Proibicoes

- E proibido implementar sem Work valida quando a tarefa seguir o fluxo de Work.
- E proibido implementar sem plano de implementacao quando a tarefa exigir plano.
- E proibido apagar ou sobrescrever planos antigos.
- E proibido apagar ou sobrescrever arquivos de controle antigos da Work.
- E proibido inventar regra de negocio.
- E proibido alterar escopo sem autorizacao.
- E proibido alterar visual sem solicitacao.
- E proibido alterar permissoes sem solicitacao.
- E proibido alterar integracao sem avaliar contrato.
- E proibido fazer deploy em producao sem pedido explicito.
- E proibido fazer deploy em full sandbox sem pedido explicito.
- E proibido usar `package.xml` completo para deploy sem autorizacao explicita.
- E proibido fazer deploy de componentes nao relacionados.
- E proibido usar dados reais em teste.
- E proibido usar `SeeAllData=true` sem justificativa.
- E proibido adicionar dependencia externa sem explicar motivo.
- E proibido remover codigo aparentemente nao usado sem verificar referencias.
- E proibido gerar solucao grande quando uma alteracao pequena resolve.
- E proibido criar arquitetura nova se o projeto ja tem padrao claro.
- E proibido sobrescrever codigo de outras pessoas.
- E proibido descartar alteracoes locais de outros desenvolvedores.
- E proibido executar comando destrutivo sem autorizacao.
- E proibido criar Custom Metadata novo sem verificar reaproveitamento e sem confirmacao.
- E proibido criar objeto, campo, flow, trigger, classe base, servico generico ou arquitetura nova sem avaliar se ja existe algo reutilizavel.
- E proibido finalizar sem informar como validar.
- E proibido afirmar que executou teste, deploy ou comando sem realmente ter executado.
