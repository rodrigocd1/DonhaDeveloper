public without sharing class LeadDeduplicacaoService {

    private static final String TIPO_TASK_REITERACAO = 'Reiteração';
    private static final String STATUS_TASK_ABERTA = 'Aberta';
    private static final String STATUS_TASK_CONCLUIDA = 'Concluída';

    private static final String SUBJECT_REITERACAO = 'Reiteração de Lead';

    /**
     * Localiza o Lead principal usando a mesma normalização da deduplicação vigente.
     * CPF continua soberano. Sem CPF, a precedência funcional da W-019640 é
     * celular/WhatsApp e depois e-mail. O ORDER BY torna determinística a escolha
     * do registro mais antigo.
     */
    public static Lead buscarLeadPrincipal(String cpf, String celular, String email) {
        String cpfNormalizado = normalizarSomenteDigitos(cpf);
        if (!String.isBlank(cpfNormalizado)) {
            Set<String> variacoesCpf = gerarVariacoesCpf(cpf, cpfNormalizado);
            List<Lead> leadsPorCpf = queryLeadsByCpf(variacoesCpf, true);
            return leadsPorCpf.isEmpty() ? null : bloquearLeadPrincipal(leadsPorCpf[0].Id);
        }

        String celularNormalizado = normalizarSomenteDigitos(celular);
        if (!String.isBlank(celularNormalizado)) {
            Set<String> variacoesCelular = gerarVariacoesCelular(celular, celularNormalizado);
            List<Lead> leadsPorCelular = [
                SELECT Id, OwnerId, CreatedDate, Email, MobilePhone, LastName, Company
                FROM Lead
                WHERE MobilePhone IN :variacoesCelular
                ORDER BY CreatedDate ASC, Id ASC
                LIMIT 1
            ];
            if (!leadsPorCelular.isEmpty()) {
                return bloquearLeadPrincipal(leadsPorCelular[0].Id);
            }
        }

        String emailNormalizado = normalizarEmail(email);
        if (!String.isBlank(emailNormalizado)) {
            Set<String> variacoesEmail = gerarVariacoesEmail(email, emailNormalizado);
            List<Lead> leadsPorEmail = [
                SELECT Id, OwnerId, CreatedDate, Email, MobilePhone, LastName, Company
                FROM Lead
                WHERE Email IN :variacoesEmail
                ORDER BY CreatedDate ASC, Id ASC
                LIMIT 1
            ];
            if (!leadsPorEmail.isEmpty()) {
                return bloquearLeadPrincipal(leadsPorEmail[0].Id);
            }
        }
        return null;
    }

    private static Lead bloquearLeadPrincipal(Id leadId) {
        return [
            SELECT Id, OwnerId, CreatedDate, Email, MobilePhone, LastName, Company
            FROM Lead
            WHERE Id = :leadId
            LIMIT 1
            FOR UPDATE
        ];
    }

    private class ResultadoDuplicidade {
        Lead leadPai;
        String criterio;

        ResultadoDuplicidade(Lead leadPai, String criterio) {
            this.leadPai = leadPai;
            this.criterio = criterio;
        }
    }

    private class DadosEntrada {
        Integer indice;
        Lead lead;

        String cpfNormalizado;
        String emailNormalizado;
        String celularNormalizado;

        DadosEntrada(Integer indice, Lead lead) {
            this.indice = indice;
            this.lead = lead;

            this.cpfNormalizado = normalizarSomenteDigitos((String) lead.get('CPF__c'));
            this.emailNormalizado = normalizarEmail(lead.Email);
            this.celularNormalizado = normalizarSomenteDigitos(lead.MobilePhone);
        }

        Boolean possuiCpf() {
            return !String.isBlank(cpfNormalizado);
        }
    }

    public static void tratarBeforeInsert(List<Lead> novosLeads) {
    if (novosLeads == null || novosLeads.isEmpty()) {
        return;
    }

    Set<String> cpfsAceitosNoLote = new Set<String>();
    Set<String> emailsAceitosNoLote = new Set<String>();
    Set<String> celularesAceitosNoLote = new Set<String>();

    for (Integer i = 0; i < novosLeads.size(); i++) {
        DadosEntrada entrada = new DadosEntrada(i, novosLeads[i]);

        bloquearDuplicidadeNoMesmoLote(
            entrada,
            cpfsAceitosNoLote,
            emailsAceitosNoLote,
            celularesAceitosNoLote
        );
    }
}

    private static ResultadoDuplicidade identificarDuplicidade(
        DadosEntrada entrada,
        Map<String, Lead> leadPorCpf,
        Map<String, Lead> leadPorEmail,
        Map<String, Lead> leadPorCelular
    ) {
        /*
         * CPF é soberano.
         *
         * Se o novo Lead tem CPF, busca apenas por CPF.
         * Mesmo que e-mail ou celular sejam iguais a outro Lead,
         * não bloqueia se o CPF for diferente.
         */
        if (entrada.possuiCpf()) {
            Lead leadPaiCpf = leadPorCpf.get(entrada.cpfNormalizado);

            if (leadPaiCpf != null) {
                return new ResultadoDuplicidade(leadPaiCpf, 'CPF');
            }

            return null;
        }

        if (!String.isBlank(entrada.celularNormalizado)) {
            Lead leadPaiCelular = leadPorCelular.get(entrada.celularNormalizado);

            if (leadPaiCelular != null) {
                return new ResultadoDuplicidade(leadPaiCelular, 'Celular');
            }
        }

        if (!String.isBlank(entrada.emailNormalizado)) {
            Lead leadPaiEmail = leadPorEmail.get(entrada.emailNormalizado);

            if (leadPaiEmail != null) {
                return new ResultadoDuplicidade(leadPaiEmail, 'E-mail');
            }
        }

        return null;
    }

    private static void bloquearDuplicidadeNoMesmoLote(
        DadosEntrada entrada,
        Set<String> cpfsAceitosNoLote,
        Set<String> emailsAceitosNoLote,
        Set<String> celularesAceitosNoLote
    ) {
        if (entrada.possuiCpf()) {
            if (cpfsAceitosNoLote.contains(entrada.cpfNormalizado)) {
                entrada.lead.addError(
                    'Lead duplicado identificado no mesmo lote por CPF. Apenas a primeira ocorrência será criada.'
                );
                return;
            }

            cpfsAceitosNoLote.add(entrada.cpfNormalizado);
            return;
        }

        if (!String.isBlank(entrada.celularNormalizado)) {
            if (celularesAceitosNoLote.contains(entrada.celularNormalizado)) {
                entrada.lead.addError(
                    'Lead duplicado identificado no mesmo lote por Celular. Apenas a primeira ocorrência será criada.'
                );
                return;
            }

            celularesAceitosNoLote.add(entrada.celularNormalizado);
        }

        if (!String.isBlank(entrada.emailNormalizado)) {
            if (emailsAceitosNoLote.contains(entrada.emailNormalizado)) {
                entrada.lead.addError(
                    'Lead duplicado identificado no mesmo lote por E-mail. Apenas a primeira ocorrência será criada.'
                );
                return;
            }

            emailsAceitosNoLote.add(entrada.emailNormalizado);
        }
    }

    private static void criarTasksReiteracao(
        List<Lead> novosLeads,
        Map<Integer, ResultadoDuplicidade> duplicidadesEncontradas
    ) {
        Set<Id> leadPaiIds = new Set<Id>();

        for (ResultadoDuplicidade resultado : duplicidadesEncontradas.values()) {
            leadPaiIds.add(resultado.leadPai.Id);
        }

        Set<Id> leadsComReiteracaoAbertaHoje = new Set<Id>();

        for (Task taskExistente : [
            SELECT Id, WhoId
            FROM Task
            WHERE WhoId IN :leadPaiIds
            AND Type = :TIPO_TASK_REITERACAO
            AND Status = :STATUS_TASK_ABERTA
            AND CreatedDate = TODAY
        ]) {
            leadsComReiteracaoAbertaHoje.add(taskExistente.WhoId);
        }

        List<Task> tasksParaInserir = new List<Task>();

        for (Integer indice : duplicidadesEncontradas.keySet()) {
            ResultadoDuplicidade resultado = duplicidadesEncontradas.get(indice);
            Lead tentativa = novosLeads[indice];

            Boolean jaExisteAbertaHoje = leadsComReiteracaoAbertaHoje.contains(resultado.leadPai.Id);

            String statusTask = jaExisteAbertaHoje
                ? STATUS_TASK_CONCLUIDA
                : STATUS_TASK_ABERTA;

            Task novaTask = new Task();
            novaTask.WhoId = resultado.leadPai.Id;
            novaTask.OwnerId = resultado.leadPai.OwnerId;
            novaTask.Type = TIPO_TASK_REITERACAO;
            novaTask.Subject = SUBJECT_REITERACAO + ' - Duplicidade por ' + resultado.criterio;
            novaTask.Status = statusTask;
            novaTask.ActivityDate = Date.today().addDays(1);
            novaTask.Description = montarDescricaoTask(tentativa, resultado);

            tasksParaInserir.add(novaTask);

            if (statusTask == STATUS_TASK_ABERTA) {
                leadsComReiteracaoAbertaHoje.add(resultado.leadPai.Id);
            }
        }

        if (!tasksParaInserir.isEmpty()) {
            insert tasksParaInserir;
        }
    }

    public static void sincronizarOwnerTasks(List<Lead> novosLeads, Map<Id, Lead> oldMap) {
        if (novosLeads == null || novosLeads.isEmpty() || oldMap == null || oldMap.isEmpty()) {
            return;
        }

        Map<Id, Id> novoOwnerPorLeadId = new Map<Id, Id>();

        for (Lead leadAtual : novosLeads) {
            Lead leadAntigo = oldMap.get(leadAtual.Id);

            if (leadAntigo != null && leadAtual.OwnerId != leadAntigo.OwnerId) {
                novoOwnerPorLeadId.put(leadAtual.Id, leadAtual.OwnerId);
            }
        }

        if (novoOwnerPorLeadId.isEmpty()) {
            return;
        }

        List<Task> tasksParaAtualizar = new List<Task>();

        for (Task taskReiteracao : [
            SELECT Id, WhoId, OwnerId
            FROM Task
            WHERE WhoId IN :novoOwnerPorLeadId.keySet()
            AND Type = :TIPO_TASK_REITERACAO
        ]) {
            Id novoOwnerId = novoOwnerPorLeadId.get(taskReiteracao.WhoId);

            if (novoOwnerId != null && taskReiteracao.OwnerId != novoOwnerId) {
                taskReiteracao.OwnerId = novoOwnerId;
                tasksParaAtualizar.add(taskReiteracao);
            }
        }

        if (!tasksParaAtualizar.isEmpty()) {
            update tasksParaAtualizar;
        }
    }

    private static Map<String, Lead> buscarLeadsPorCpf(Set<String> valoresCpf, Set<Id> idsIgnorados) {
        Map<String, Lead> leadPorCpf = new Map<String, Lead>();

        if (valoresCpf == null || valoresCpf.isEmpty()) {
            return leadPorCpf;
        }

        for (Lead leadExistente : queryLeadsByCpf(valoresCpf, false)) {
            if (idsIgnorados != null && idsIgnorados.contains(leadExistente.Id)) {
    			continue;
			}
            
            String cpfNormalizado = normalizarSomenteDigitos((String) leadExistente.get('CPF__c'));

            if (!String.isBlank(cpfNormalizado) && !leadPorCpf.containsKey(cpfNormalizado)) {
                leadPorCpf.put(cpfNormalizado, leadExistente);
            }
        }

        return leadPorCpf;
    }

    private static Map<String, Lead> buscarLeadsPorEmail(Set<String> valoresEmail, Set<Id> idsIgnorados) {
        Map<String, Lead> leadPorEmail = new Map<String, Lead>();

        if (valoresEmail == null || valoresEmail.isEmpty()) {
            return leadPorEmail;
        }

        for (Lead leadExistente : [
            SELECT Id, OwnerId, CreatedDate, Email, MobilePhone, LastName, Company
            FROM Lead
            WHERE Email IN :valoresEmail
            ORDER BY CreatedDate ASC, Id ASC
        ]) {
            if (idsIgnorados != null && idsIgnorados.contains(leadExistente.Id)) {
    		continue;
			}
            String emailNormalizado = normalizarEmail(leadExistente.Email);

            if (!String.isBlank(emailNormalizado) && !leadPorEmail.containsKey(emailNormalizado)) {
                leadPorEmail.put(emailNormalizado, leadExistente);
            }
        }

        return leadPorEmail;
    }

    private static Map<String, Lead> buscarLeadsPorCelular(Set<String> valoresCelular, Set<Id> idsIgnorados) {
        Map<String, Lead> leadPorCelular = new Map<String, Lead>();

        if (valoresCelular == null || valoresCelular.isEmpty()) {
            return leadPorCelular;
        }

        for (Lead leadExistente : [
            SELECT Id, OwnerId, CreatedDate, Email, MobilePhone, LastName, Company
            FROM Lead
            WHERE MobilePhone IN :valoresCelular
            ORDER BY CreatedDate ASC, Id ASC
        ]) {
            if (idsIgnorados != null && idsIgnorados.contains(leadExistente.Id)) {
    		continue;
			}
            String celularNormalizado = normalizarSomenteDigitos(leadExistente.MobilePhone);

            if (!String.isBlank(celularNormalizado) && !leadPorCelular.containsKey(celularNormalizado)) {
                leadPorCelular.put(celularNormalizado, leadExistente);
            }
        }

        return leadPorCelular;
    }

    /**
     * O Guest não recebe FLS direto ao CPF. As consultas internas que realmente
     * precisam desse identificador executam em modo de sistema dentro desta classe
     * sem compartilhamento, sem retornar o valor ao controller público.
     */
    private static List<Lead> queryLeadsByCpf(Set<String> cpfValues, Boolean limitOne) {
        String queryText =
            'SELECT Id, OwnerId, CreatedDate, CPF__c, Email, MobilePhone, LastName, Company ' +
            'FROM Lead WHERE CPF__c IN :cpfValues ORDER BY CreatedDate ASC, Id ASC' +
            (limitOne ? ' LIMIT 1' : '');
        return (List<Lead>) Database.queryWithBinds(
            queryText,
            new Map<String, Object>{ 'cpfValues' => cpfValues },
            AccessLevel.SYSTEM_MODE
        );
    }

    private static void bloquearLeadsSelecionados(
        Map<String, Lead> leadPorCpf,
        Map<String, Lead> leadPorEmail,
        Map<String, Lead> leadPorCelular
    ) {
        Set<Id> leadIds = new Set<Id>();
        for (Lead record : leadPorCpf.values()) {
            leadIds.add(record.Id);
        }
        for (Lead record : leadPorEmail.values()) {
            leadIds.add(record.Id);
        }
        for (Lead record : leadPorCelular.values()) {
            leadIds.add(record.Id);
        }
        if (!leadIds.isEmpty()) {
            List<Lead> lockedRecords = [SELECT Id FROM Lead WHERE Id IN :leadIds FOR UPDATE];
        }
    }

    private static String montarDescricaoTask(Lead tentativa, ResultadoDuplicidade resultado) {
        List<String> linhas = new List<String>();

        linhas.add('Tentativa de criação de Lead bloqueada por duplicidade.');
        linhas.add('Critério encontrado: ' + resultado.criterio);
        linhas.add('Lead Pai: ' + resultado.leadPai.Id);
        linhas.add('Data/Hora da tentativa: ' + Datetime.now().format('dd/MM/yyyy HH:mm:ss'));
        linhas.add('');
        linhas.add('Dados recebidos na nova tentativa:');
        linhas.add('Nome: ' + valorTexto(tentativa.LastName));
        linhas.add('Empresa: ' + valorTexto(tentativa.Company));
        linhas.add('CPF: ' + valorTexto((String) tentativa.get('CPF__c')));
        linhas.add('E-mail: ' + valorTexto(tentativa.Email));
        linhas.add('Celular: ' + valorTexto(tentativa.MobilePhone));

        return String.join(linhas, '\n');
    }

    private static String valorTexto(String valor) {
        return String.isBlank(valor) ? '-' : valor;
    }

    private static String normalizarSomenteDigitos(String valor) {
        if (String.isBlank(valor)) {
            return null;
        }

        String normalizado = valor.replaceAll('[^0-9]', '');

        return String.isBlank(normalizado) ? null : normalizado;
    }

    private static String normalizarEmail(String valor) {
        if (String.isBlank(valor)) {
            return null;
        }

        String normalizado = valor.replaceAll('\\s+', '').toLowerCase();

        return String.isBlank(normalizado) ? null : normalizado;
    }

    private static Set<String> gerarVariacoesCpf(String valorOriginal, String cpfNormalizado) {
        Set<String> variacoes = new Set<String>();

        if (!String.isBlank(valorOriginal)) {
            variacoes.add(valorOriginal.trim());
        }

        if (!String.isBlank(cpfNormalizado)) {
            variacoes.add(cpfNormalizado);

            if (cpfNormalizado.length() == 11) {
                variacoes.add(
                    cpfNormalizado.substring(0, 3) + '.' +
                    cpfNormalizado.substring(3, 6) + '.' +
                    cpfNormalizado.substring(6, 9) + '-' +
                    cpfNormalizado.substring(9, 11)
                );
            }
        }

        return variacoes;
    }

    private static Set<String> gerarVariacoesEmail(String valorOriginal, String emailNormalizado) {
        Set<String> variacoes = new Set<String>();

        if (!String.isBlank(valorOriginal)) {
            variacoes.add(valorOriginal.trim());
        }

        if (!String.isBlank(emailNormalizado)) {
            variacoes.add(emailNormalizado);
        }

        return variacoes;
    }

    private static Set<String> gerarVariacoesCelular(String valorOriginal, String celularNormalizado) {
        Set<String> variacoes = new Set<String>();

        if (!String.isBlank(valorOriginal)) {
            variacoes.add(valorOriginal.trim());
        }

        if (!String.isBlank(celularNormalizado)) {
            variacoes.add(celularNormalizado);

            if (celularNormalizado.length() == 11) {
                String ddd = celularNormalizado.substring(0, 2);
                String parte1 = celularNormalizado.substring(2, 7);
                String parte2 = celularNormalizado.substring(7, 11);

                variacoes.add('(' + ddd + ') ' + parte1 + '-' + parte2);
                variacoes.add(ddd + ' ' + parte1 + '-' + parte2);
            }

            if (celularNormalizado.length() == 10) {
                String ddd = celularNormalizado.substring(0, 2);
                String parte1 = celularNormalizado.substring(2, 6);
                String parte2 = celularNormalizado.substring(6, 10);

                variacoes.add('(' + ddd + ') ' + parte1 + '-' + parte2);
                variacoes.add(ddd + ' ' + parte1 + '-' + parte2);
            }
        }

        return variacoes;
    }
    public static void tratarAfterInsert(List<Lead> novosLeads) {
    if (novosLeads == null || novosLeads.isEmpty()) {
        return;
    }

    List<DadosEntrada> entradas = new List<DadosEntrada>();
    Set<Id> novosLeadIds = new Set<Id>();

    Set<String> valoresCpfParaConsulta = new Set<String>();
    Set<String> valoresEmailParaConsulta = new Set<String>();
    Set<String> valoresCelularParaConsulta = new Set<String>();

    for (Integer i = 0; i < novosLeads.size(); i++) {
        Lead leadNovo = novosLeads[i];
        novosLeadIds.add(leadNovo.Id);

        DadosEntrada entrada = new DadosEntrada(i, leadNovo);
        entradas.add(entrada);

        if (entrada.possuiCpf()) {
            valoresCpfParaConsulta.addAll(
                gerarVariacoesCpf((String) entrada.lead.get('CPF__c'), entrada.cpfNormalizado)
            );
        } else {
            if (!String.isBlank(entrada.emailNormalizado)) {
                valoresEmailParaConsulta.addAll(
                    gerarVariacoesEmail(entrada.lead.Email, entrada.emailNormalizado)
                );
            }

            if (!String.isBlank(entrada.celularNormalizado)) {
                valoresCelularParaConsulta.addAll(
                    gerarVariacoesCelular(entrada.lead.MobilePhone, entrada.celularNormalizado)
                );
            }
        }
    }

    Map<String, Lead> leadPorCpf = buscarLeadsPorCpf(valoresCpfParaConsulta, novosLeadIds);
    Map<String, Lead> leadPorEmail = buscarLeadsPorEmail(valoresEmailParaConsulta, novosLeadIds);
    Map<String, Lead> leadPorCelular = buscarLeadsPorCelular(valoresCelularParaConsulta, novosLeadIds);
    bloquearLeadsSelecionados(leadPorCpf, leadPorEmail, leadPorCelular);

    Map<Integer, ResultadoDuplicidade> duplicidadesEncontradas = new Map<Integer, ResultadoDuplicidade>();

    for (DadosEntrada entrada : entradas) {
        ResultadoDuplicidade resultado = identificarDuplicidade(
            entrada,
            leadPorCpf,
            leadPorEmail,
            leadPorCelular
        );

        if (resultado != null) {
            duplicidadesEncontradas.put(entrada.indice, resultado);
        }
    }

    if (duplicidadesEncontradas.isEmpty()) {
        return;
    }

    criarTasksReiteracao(novosLeads, duplicidadesEncontradas);

    List<Lead> leadsDuplicadosParaExcluir = new List<Lead>();

    for (Integer indice : duplicidadesEncontradas.keySet()) {
        leadsDuplicadosParaExcluir.add(new Lead(
            Id = novosLeads[indice].Id
        ));
    }

    if (!leadsDuplicadosParaExcluir.isEmpty()) {
        delete leadsDuplicadosParaExcluir;
    }
}
}