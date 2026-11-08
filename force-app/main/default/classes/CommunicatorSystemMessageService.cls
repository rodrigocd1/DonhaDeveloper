/**
 * @description Handles automatic creation of system messages in the Communicator chat
 *              triggered by business process events (AR, AB, Opportunity phase, Repasse).
 *              Uses without sharing because it runs in trigger context and must write
 *              regardless of the initiating user's permissions.
 */
public without sharing class CommunicatorSystemMessageService {
    private static final String OPP_CONTRATO_ASSINADO_GANHA = 'Contrato Assinado - Oppty Ganha';
    private static final String OPP_FECHADO_PERDIDO = 'Fechado e perdido';
    private static final String OPP_ENCERRADA_REPASSE_MSG =
        'Etapa da oportunidade encerrada. A partir de agora, o comunicador segue na etapa de repasse.';
    private static final String OPP_ENCERRADA_PERDIDA_MSG =
        'Envio de mensagens bloqueado: oportunidade encerrada e perdida.';
    private static final String EVT_AR_AC     = 'Análise de Renda/Crédito';
    private static final String EVT_AB        = 'Aprovação Bancária';
    private static final String EVT_OPP_PHASE = 'Fase da Oportunidade';
    private static final String EVT_OPP_CLOSE = 'Encerramento da Oportunidade';
    private static final String EVT_REPASSE   = 'Fase do Repasse';
    private static final Set<String> REPASSE_MACRO_PHASES = new Set<String>{
        'Aguardando início',
        'Formulário',
        'Conferência de dossiê',
        'Pendências',
        'Assinatura do repasse',
        'Retenção',
        'Triagem',
        'Outros'
    };
    private static final Set<String> AR_MONITORED_STATUSES = new Set<String>{
        'Reprovado', 'Aprovado', 'Não iniciado', 'Em análise', 'Na Agência', 'Vencido'
    };
    private static final Set<String> AR_TERMINAL_STATUSES = new Set<String>{ 'Reprovado', 'Aprovado' };
    private static final String AR_STAGE = 'Apuração de Renda';
    private static final String AC_STAGE = 'Análise de Crédito';


    // ─────────────────────────────────────────
    // AR — AnaliseFinanceira__c status change
    // ─────────────────────────────────────────

    /**
     * @description Called from ApuracaoRendaTriggerHandler.afterUpdate.
     *              Sends a system message when Status__c changes to any monitored AR status.
     *              Terminal statuses (Aprovado/Reprovado) route to the latest active thread;
     *              progress statuses target the 'Apuração de Renda' stage thread.
     */
    public static void sendARStatusMessages(
        List<AnaliseFinanceira__c> newList,
        Map<Id, AnaliseFinanceira__c> oldMap
    ) {
        // Collect IDs where Status__c changed to any monitored status
        Set<Id> changedIds = new Set<Id>();
        Map<Id, String> newStatusById = new Map<Id, String>();
        for (AnaliseFinanceira__c af : newList) {
            AnaliseFinanceira__c prev = (oldMap != null) ? oldMap.get(af.Id) : null;
            if (prev == null || af.Status__c == prev.Status__c) continue;
            if (!AR_MONITORED_STATUSES.contains(af.Status__c)) continue;
            changedIds.add(af.Id);
            newStatusById.put(af.Id, af.Status__c);
        }
        if (changedIds.isEmpty()) return;

        // Query RecordType DeveloperName, Oportunidade__c and MotivoParecer__c in one pass
        Map<Id, AnaliseFinanceira__c> afDetails = new Map<Id, AnaliseFinanceira__c>([
            SELECT Id, RecordType.DeveloperName, Oportunidade__c, MotivoParecer__c
            FROM AnaliseFinanceira__c
            WHERE Id IN :changedIds
        ]);

        // Separate standard AR (ApuracaoRendaOportunidade) from AC (AnaliseCredito)
        Set<Id> arIds = new Set<Id>();
        Set<Id> acIds = new Set<Id>();
        for (AnaliseFinanceira__c af : afDetails.values()) {
            if (af.RecordType.DeveloperName == 'AnaliseCredito') {
                acIds.add(af.Id);
            } else {
                arIds.add(af.Id);
            }
        }

        // Separate AR terminal (Aprovado/Reprovado) from AR progress statuses
        Set<Id> terminalArIds = new Set<Id>();
        Set<Id> progressArIds = new Set<Id>();
        for (Id afId : arIds) {
            if (AR_TERMINAL_STATUSES.contains(newStatusById.get(afId))) {
                terminalArIds.add(afId);
            } else {
                progressArIds.add(afId);
            }
        }

        // Query rejected documents for all reprovado records (field works regardless of RT)
        Set<Id> reprovadoIds = new Set<Id>();
        for (Id afId : changedIds) {
            if (newStatusById.get(afId) == 'Reprovado') reprovadoIds.add(afId);
        }
        Map<Id, List<DocumentoChecklist__c>> docsByAnalise = new Map<Id, List<DocumentoChecklist__c>>();
        if (!reprovadoIds.isEmpty()) {
            for (DocumentoChecklist__c doc : [
                SELECT Name, IdDocumento__c, StatusAprovacao__c, Observacoes__c,
                       ApuracaoRendaOportunidade__c
                FROM DocumentoChecklist__c
                WHERE ApuracaoRendaOportunidade__c IN :reprovadoIds
                AND   StatusAprovacao__c LIKE 'Reprovado%'
            ]) {
                Id key = doc.ApuracaoRendaOportunidade__c;
                if (!docsByAnalise.containsKey(key)) docsByAnalise.put(key, new List<DocumentoChecklist__c>());
                docsByAnalise.get(key).add(doc);
            }
        }

        Map<Id, String> threadToBody = new Map<Id, String>();

        // ── AR terminal (Aprovado/Reprovado): target the opportunity's current stage thread ──
        // Querying StageName here reflects the phase the opportunity has moved to (e.g., back to
        // 'Montagem de pasta' on rejection), so the message lands in the correct tab.
        if (!terminalArIds.isEmpty()) {
            Map<Id, Id> arAnaliseToOpp = new Map<Id, Id>();
            Map<Id, String> arOppToCurrentStage = new Map<Id, String>();
            for (Opportunity opp : [
                SELECT Id, ApuracaoRenda__c, StageName
                FROM Opportunity
                WHERE ApuracaoRenda__c IN :terminalArIds
            ]) {
                arAnaliseToOpp.put(opp.ApuracaoRenda__c, opp.Id);
                arOppToCurrentStage.put(opp.Id, opp.StageName);
            }
            Map<Id, Id> arOppToThread = findOrCreateThreadByOppIdAndStage(arOppToCurrentStage);
            for (Id afId : terminalArIds) {
                Id oppId    = arAnaliseToOpp.get(afId);
                Id threadId = (oppId != null) ? arOppToThread.get(oppId) : null;
                if (threadId == null) continue;
                AnaliseFinanceira__c af = afDetails.get(afId);
                if (newStatusById.get(afId) == 'Reprovado') {
                    threadToBody.put(threadId, buildARReprovadoBody(af.MotivoParecer__c, docsByAnalise.get(afId)));
                } else {
                    String body = 'Análise de renda aprovada com sucesso. A oportunidade está pronta para avançar.';
                    if (String.isNotBlank(af.MotivoParecer__c)) body += '\nMotivo: ' + af.MotivoParecer__c;
                    threadToBody.put(threadId, body);
                }
            }
        }

        // ── AR progress (Não iniciado/Em análise/Na Agência/Vencido): target 'Apuração de Renda' thread ──
        if (!progressArIds.isEmpty()) {
            Map<Id, Id> arAnaliseToOpp = new Map<Id, Id>();
            for (Opportunity opp : [
                SELECT Id, ApuracaoRenda__c
                FROM Opportunity
                WHERE ApuracaoRenda__c IN :progressArIds
            ]) {
                arAnaliseToOpp.put(opp.ApuracaoRenda__c, opp.Id);
            }
            Map<Id, String> oppIdToStage = new Map<Id, String>();
            for (Id afId : progressArIds) {
                Id oppId = arAnaliseToOpp.get(afId);
                if (oppId != null) oppIdToStage.put(oppId, AR_STAGE);
            }
            Map<Id, Id> arOppToThread = findOrCreateThreadByOppIdAndStage(oppIdToStage);
            for (Id afId : progressArIds) {
                Id oppId    = arAnaliseToOpp.get(afId);
                Id threadId = (oppId != null) ? arOppToThread.get(oppId) : null;
                if (threadId == null) continue;
                String body = buildARProgressBody(newStatusById.get(afId));
                if (String.isNotBlank(body)) threadToBody.put(threadId, body);
            }
        }

        // ── AC: opportunity linked via AnaliseFinanceira__c.Oportunidade__c ──
        if (!acIds.isEmpty()) {
            // Separate AC terminal (Aprovado/Reprovado) from AC progress statuses
            Set<Id> terminalAcIds = new Set<Id>();
            Set<Id> progressAcIds = new Set<Id>();
            for (Id afId : acIds) {
                if (AR_TERMINAL_STATUSES.contains(newStatusById.get(afId))) {
                    terminalAcIds.add(afId);
                } else {
                    progressAcIds.add(afId);
                }
            }

            // Collect all AC opportunity IDs in one pass
            Map<Id, Id> acAnaliseToOpp = new Map<Id, Id>();
            for (Id afId : acIds) {
                AnaliseFinanceira__c af = afDetails.get(afId);
                if (af.Oportunidade__c != null) acAnaliseToOpp.put(afId, af.Oportunidade__c);
            }

            // ── AC terminal (Aprovado/Reprovado): target the opportunity's current stage thread ──
            if (!terminalAcIds.isEmpty()) {
                Set<Id> acOppIds = new Set<Id>();
                for (Id afId : terminalAcIds) {
                    if (acAnaliseToOpp.get(afId) != null) acOppIds.add(acAnaliseToOpp.get(afId));
                }
                Map<Id, String> acOppToCurrentStage = new Map<Id, String>();
                for (Opportunity opp : [SELECT Id, StageName FROM Opportunity WHERE Id IN :acOppIds]) {
                    acOppToCurrentStage.put(opp.Id, opp.StageName);
                }
                Map<Id, Id> acOppToThread = findOrCreateThreadByOppIdAndStage(acOppToCurrentStage);
                for (Id afId : terminalAcIds) {
                    AnaliseFinanceira__c af = afDetails.get(afId);
                    Id oppId    = acAnaliseToOpp.get(afId);
                    Id threadId = (oppId != null) ? acOppToThread.get(oppId) : null;
                    if (threadId == null) continue;
                    if (newStatusById.get(afId) == 'Reprovado') {
                        threadToBody.put(threadId, buildACReprovadoBody(af.MotivoParecer__c, docsByAnalise.get(afId)));
                    } else {
                        String body = 'Análise de crédito aprovada com sucesso. A oportunidade está pronta para avançar.';
                        if (String.isNotBlank(af.MotivoParecer__c)) body += '\nMotivo: ' + af.MotivoParecer__c;
                        threadToBody.put(threadId, body);
                    }
                }
            }

            // ── AC progress (Não iniciado/Em análise/Na Agência/Vencido): target 'Análise de Crédito' thread ──
            if (!progressAcIds.isEmpty()) {
                Map<Id, String> oppIdToStage = new Map<Id, String>();
                for (Id afId : progressAcIds) {
                    Id oppId = acAnaliseToOpp.get(afId);
                    if (oppId != null) oppIdToStage.put(oppId, AC_STAGE);
                }
                Map<Id, Id> acOppToThread = findOrCreateThreadByOppIdAndStage(oppIdToStage);
                for (Id afId : progressAcIds) {
                    Id oppId    = acAnaliseToOpp.get(afId);
                    Id threadId = (oppId != null) ? acOppToThread.get(oppId) : null;
                    if (threadId == null) continue;
                    String body = buildACProgressBody(newStatusById.get(afId));
                    if (String.isNotBlank(body)) threadToBody.put(threadId, body);
                }
            }
        }

        dispatchSystemMessages(threadToBody, EVT_AR_AC);
    }

    // ─────────────────────────────────────────
    // AB — AprovacaoBancaria__c status change
    // ─────────────────────────────────────────

    /**
     * @description Called from AprovacaoBancariaTriggerHandler.afterUpdate.
     *              Sends a system message when StatusAprovacaoBancaria__c changes to 'Aprovada'
     *              or 'Aprovada com Pendências'. Always uses the most recent valid approval.
     */
    public static void sendABApprovalMessages(
        List<AprovacaoBancaria__c> newList,
        Map<Id, AprovacaoBancaria__c> oldMap
    ) {
        Set<Id> changedIds = new Set<Id>();
        for (AprovacaoBancaria__c ab : newList) {
            AprovacaoBancaria__c prev = (oldMap != null) ? oldMap.get(ab.Id) : null;
            String newStatus = ab.StatusAprovacaoBancaria__c;
            String oldStatus = (prev != null) ? prev.StatusAprovacaoBancaria__c : null;
            if (newStatus == oldStatus) continue;
            if (newStatus == 'Aprovada' || newStatus == 'Aprovada com Pendências' || newStatus == 'Reprovada') {
                changedIds.add(ab.Id);
            }
        }
        if (changedIds.isEmpty()) return;

        Map<String, Schema.SObjectField> abFieldMap =
            AprovacaoBancaria__c.SObjectType.getDescribe().fields.getMap();
        Boolean hasPerAprovacaoParcela = abFieldMap.containsKey('PerAprovacaoParcela__c');

        String abQuery =
            'SELECT Id, StatusAprovacaoBancaria__c, IdOportunidade__c,' +
            ' ValorFinanciamento__c, LTV__c, ValorParcela__c,' +
            ' ValorSubsidio__c, ModalidadeFinanciamento__c, Observacoes__c';
        if (hasPerAprovacaoParcela) {
            abQuery += ', PerAprovacaoParcela__c';
        }
        abQuery += ' FROM AprovacaoBancaria__c WHERE Id IN :changedIds';

        Map<Id, AprovacaoBancaria__c> abById = new Map<Id, AprovacaoBancaria__c>();
        for (SObject abRow : Database.query(abQuery)) {
            AprovacaoBancaria__c abRecord = (AprovacaoBancaria__c) abRow;
            abById.put(abRecord.Id, abRecord);
        }

        Set<Id> oppIds = new Set<Id>();
        for (AprovacaoBancaria__c ab : abById.values()) {
            if (ab.IdOportunidade__c != null) oppIds.add(ab.IdOportunidade__c);
        }

        Map<Id, String> oppToStage = new Map<Id, String>();
        Map<Id, Id> oppToArId = new Map<Id, Id>();
        for (Opportunity opp : [
            SELECT Id, StageName, ApuracaoRenda__c FROM Opportunity WHERE Id IN :oppIds
        ]) {
            oppToStage.put(opp.Id, opp.StageName);
            if (opp.ApuracaoRenda__c != null) oppToArId.put(opp.Id, opp.ApuracaoRenda__c);
        }

        // Query FGTS3anos__c from AnaliseFinanceira__c linked to each Opportunity
        Set<Id> arIds = new Set<Id>(oppToArId.values());
        Map<Id, String> arIdToFgts3anos = new Map<Id, String>();
        if (!arIds.isEmpty()) {
            for (AnaliseFinanceira__c ar : [
                SELECT Id, FGTS3anos__c FROM AnaliseFinanceira__c WHERE Id IN :arIds
            ]) {
                arIdToFgts3anos.put(ar.Id, ar.FGTS3anos__c);
            }
        }
        // Map oppId -> FGTS3anos__c value
        Map<Id, String> oppToFgts3anos = new Map<Id, String>();
        for (Id oppId : oppToArId.keySet()) {
            oppToFgts3anos.put(oppId, arIdToFgts3anos.get(oppToArId.get(oppId)));
        }

        Map<Id, Id> oppToThread = findThreadByOppIdAndCurrentStage(oppIds, oppToStage);

        Map<Id, String> threadToBody = new Map<Id, String>();
        for (AprovacaoBancaria__c ab : abById.values()) {
            Id threadId = (ab.IdOportunidade__c != null) ? oppToThread.get(ab.IdOportunidade__c) : null;
            if (threadId == null) continue;
            threadToBody.put(threadId, ab.StatusAprovacaoBancaria__c == 'Reprovada'
                ? buildABReprovadoBody(ab)
                : buildABApprovalBody(ab, oppToFgts3anos.get(ab.IdOportunidade__c))
            );
        }

        dispatchSystemMessages(threadToBody, EVT_AB);
    }

    // ─────────────────────────────────────────
    // Opportunity phase change
    // ─────────────────────────────────────────

    /**
     * @description Called from OpportunityTriggerHandler.afterUpdate.
     *              Sends a system message when StageName changes to a monitored phase.
     *              Creates the thread for the new stage if it does not yet exist.
     */
    public static void sendOppPhaseMessages(
        List<Opportunity> newList,
        Map<Id, Opportunity> oldMap
    ) {
        Map<Id, String> oppToOldStage = new Map<Id, String>();
        Map<Id, String> oppToNewStage = new Map<Id, String>();
        for (Opportunity opp : newList) {
            Opportunity prev = (oldMap != null) ? oldMap.get(opp.Id) : null;
            if (prev == null || opp.StageName == prev.StageName) continue;
            oppToOldStage.put(opp.Id, prev.StageName);
            oppToNewStage.put(opp.Id, opp.StageName);
        }
        if (oppToOldStage.isEmpty()) return;

        Set<Id> oppIds = oppToOldStage.keySet();

        // Load all existing active threads for affected opps
        Map<String, Id> keyToThreadId = new Map<String, Id>();
        for (CommunicatorThread__c t : [
            SELECT Id, RecordId__c, Stage__c
            FROM CommunicatorThread__c
            WHERE RecordId__c IN :oppIds AND Status__c != 'Archived'
        ]) {
            String key = (String) t.RecordId__c + '_' + (t.Stage__c != null ? t.Stage__c : '');
            if (!keyToThreadId.containsKey(key)) keyToThreadId.put(key, t.Id);
        }

        // Create threads for new stages that don't exist yet
        List<CommunicatorThread__c> toCreate = new List<CommunicatorThread__c>();
        Map<Id, CommunicatorThread__c> oppToNewThread = new Map<Id, CommunicatorThread__c>();
        for (Id oppId : oppIds) {
            String newStage = oppToNewStage.get(oppId);
            String newKey   = (String) oppId + '_' + newStage;
            if (!keyToThreadId.containsKey(newKey)) {
                CommunicatorThread__c t = new CommunicatorThread__c(
                    RecordId__c   = oppId,
                    RecordType__c = 'Opportunity',
                    Stage__c      = newStage,
                    Status__c     = 'Active'
                );
                toCreate.add(t);
                oppToNewThread.put(oppId, t);
            }
        }
        if (!toCreate.isEmpty()) {
            insert toCreate;
            for (Id oppId : oppToNewThread.keySet()) {
                CommunicatorThread__c t = oppToNewThread.get(oppId);
                keyToThreadId.put((String) oppId + '_' + t.Stage__c, t.Id);
            }
        }

        // One message per thread: "Saindo de X." in old thread, "Entrando em Y." or "Retornando à fase Y." in new thread
        Map<Id, String> threadToBody = new Map<Id, String>();
        for (Id oppId : oppIds) {
            String oldStage    = oppToOldStage.get(oppId);
            String newStage    = oppToNewStage.get(oppId);
            Id     oldThreadId = keyToThreadId.get((String) oppId + '_' + oldStage);
            Id     newThreadId = keyToThreadId.get((String) oppId + '_' + newStage);
            if (oldThreadId != null) threadToBody.put(oldThreadId, 'Saindo de ' + oldStage + '.');
            if (newThreadId != null) {
                // If the thread was newly created we are entering a brand-new phase;
                // if it already existed the opportunity is returning to a previous phase.
                Boolean isReturn = !oppToNewThread.containsKey(oppId);
                String enterMsg  = isReturn
                    ? 'Retornando à ' + newStage + '.'
                    : 'Entrando em ' + newStage + '.';
                threadToBody.put(newThreadId, enterMsg);
            }
        }

        dispatchSystemMessages(threadToBody, EVT_OPP_PHASE);

        // When entering "Contrato Assinado - Oppty Ganha", send an extra message
        // in that thread signalling that opportunity phase is finished and repasse starts.
        Map<Id, String> repasseExtra = new Map<Id, String>();
        for (Id oppId : oppIds) {
            if (oppToNewStage.get(oppId) != OPP_CONTRATO_ASSINADO_GANHA) continue;
            Id closedStageThreadId = keyToThreadId.get((String) oppId + '_' + OPP_CONTRATO_ASSINADO_GANHA);
            if (closedStageThreadId != null) repasseExtra.put(closedStageThreadId, OPP_ENCERRADA_REPASSE_MSG);
        }
        if (!repasseExtra.isEmpty()) {
            dispatchSystemMessages(repasseExtra, EVT_OPP_CLOSE);
        }

        // When entering "Fechado e perdido", publish the closure message
        // on the "Contrato Assinado - Oppty Ganha" thread (visible tab fallback).
        Map<Id, String> lostExtra = new Map<Id, String>();
        for (Id oppId : oppIds) {
            if (oppToNewStage.get(oppId) != OPP_FECHADO_PERDIDO) continue;
            Id contratoTabThreadId = keyToThreadId.get((String) oppId + '_' + OPP_CONTRATO_ASSINADO_GANHA);
            if (contratoTabThreadId != null) {
                lostExtra.put(contratoTabThreadId, OPP_ENCERRADA_PERDIDA_MSG);
            }
        }
        if (!lostExtra.isEmpty()) {
            dispatchSystemMessages(lostExtra, EVT_OPP_CLOSE);
        }
    }

    // ─────────────────────────────────────────
    // Repasse status change
    // ─────────────────────────────────────────

    /**
     * @description Called from RepasseStatusTriggerHandler.afterInsert.
     *              Sends a system message when a new RepasseStatus__c record is inserted,
     *              indicating the Repasse has moved to a new Fase.
     */
    public static void sendRepasseStatusMessages(List<RepasseStatus__c> newList) {
        Set<Id> repasseIds = new Set<Id>();
        for (RepasseStatus__c rs : newList) {
            if (rs.Repasse__c != null) repasseIds.add(rs.Repasse__c);
        }
        if (repasseIds.isEmpty()) return;

        Map<Id, Id>     repasseToOpp       = new Map<Id, Id>();
        Map<Id, String> repasseToNomeSintese = new Map<Id, String>();
        for (Repasse__c r : [SELECT Id, Oportunidade__c, NomeSintese__c FROM Repasse__c WHERE Id IN :repasseIds]) {
            if (r.Oportunidade__c != null) repasseToOpp.put(r.Id, r.Oportunidade__c);
            if (String.isNotBlank(r.NomeSintese__c)) repasseToNomeSintese.put(r.Id, r.NomeSintese__c);
        }

        Set<Id> oppIds = new Set<Id>(repasseToOpp.values());

        // Build a map of oppId → macroPhase. Unmapped NomeSintese values resolve to 'Outros'.
        Map<Id, String> oppToMacroPhase  = new Map<Id, String>();
        Map<Id, String> oppToRawSintese  = new Map<Id, String>();

        for (RepasseStatus__c rs : newList) {
            if (rs.Repasse__c == null) continue;
            Id oppId = repasseToOpp.get(rs.Repasse__c);
            if (oppId == null) continue;
            String faseName   = repasseToNomeSintese.get(rs.Repasse__c);
            if (String.isBlank(faseName)) continue;
            String macroPhase = CommunicatorRepassePhaseHelper.getMacroPhase(faseName);
            if (String.isNotBlank(macroPhase)) {
                oppToMacroPhase.put(oppId, macroPhase);
                if (macroPhase == 'Outros') oppToRawSintese.put(oppId, faseName);
            }
        }

        Map<Id, String> threadToBody = new Map<Id, String>();

        // ── Mapped: create/find a phase-specific thread ──────────────────────
        if (!oppToMacroPhase.isEmpty()) {
            Set<Id> mappedOppIds = oppToMacroPhase.keySet();
            Map<String, Id> keyToThreadId = new Map<String, Id>();
            Map<Id, String> oppToLatestRepasseStage = new Map<Id, String>();
            for (CommunicatorThread__c t : [
                SELECT Id, RecordId__c, Stage__c, LastMessageAt__c, CreatedDate
                FROM CommunicatorThread__c
                WHERE RecordId__c IN :mappedOppIds
                AND   Status__c  != 'Archived'
                ORDER BY RecordId__c, LastMessageAt__c DESC NULLS LAST, CreatedDate DESC
            ]) {
                String key = (String) t.RecordId__c + '_' + (t.Stage__c != null ? t.Stage__c : '');
                if (!keyToThreadId.containsKey(key)) keyToThreadId.put(key, t.Id);
                if (!oppToLatestRepasseStage.containsKey(t.RecordId__c) && isRepasseMacroPhase(t.Stage__c)) {
                    oppToLatestRepasseStage.put(t.RecordId__c, t.Stage__c);
                }
            }

            List<CommunicatorThread__c> toCreate = new List<CommunicatorThread__c>();
            Map<Id, CommunicatorThread__c> oppToNewThread = new Map<Id, CommunicatorThread__c>();
            for (Id oppId : mappedOppIds) {
                String newStage = oppToMacroPhase.get(oppId);
                String newKey   = (String) oppId + '_' + newStage;
                if (!keyToThreadId.containsKey(newKey)) {
                    CommunicatorThread__c t = new CommunicatorThread__c(
                        RecordId__c   = oppId,
                        RecordType__c = 'Opportunity',
                        Stage__c      = newStage,
                        Status__c     = 'Active'
                    );
                    toCreate.add(t);
                    oppToNewThread.put(oppId, t);
                }
            }
            if (!toCreate.isEmpty()) {
                insert toCreate;
                for (Id oppId : oppToNewThread.keySet()) {
                    CommunicatorThread__c t = oppToNewThread.get(oppId);
                    keyToThreadId.put((String) oppId + '_' + t.Stage__c, t.Id);
                }
            }

            for (Id oppId : oppToMacroPhase.keySet()) {
                String oldStage = oppToLatestRepasseStage.get(oppId);
                String newStage = oppToMacroPhase.get(oppId);

                if (String.isBlank(newStage)) continue;
                if (String.isNotBlank(oldStage) && oldStage == newStage) continue;

                Id oldThreadId = String.isNotBlank(oldStage)
                    ? keyToThreadId.get((String) oppId + '_' + oldStage)
                    : null;
                Id newThreadId = keyToThreadId.get((String) oppId + '_' + newStage);

                if (oldThreadId != null) {
                    threadToBody.put(oldThreadId, 'Saindo de ' + oldStage + '.');
                }
                if (newThreadId != null) {
                    String enterMsg;
                    if (newStage == 'Outros') {
                        String rawSintese = oppToRawSintese.get(oppId);
                        enterMsg = 'A etapa \'' + rawSintese + '\' não possui uma fase mapeada. Entrando em Outros.';
                    } else {
                        Boolean isReturn = !oppToNewThread.containsKey(oppId);
                        enterMsg = isReturn
                            ? 'Retornando à ' + newStage + '.'
                            : 'Entrando em ' + newStage + '.';
                    }
                    threadToBody.put(newThreadId, enterMsg);
                }
            }
        }

        if (threadToBody.isEmpty()) return;

        dispatchSystemMessages(threadToBody, EVT_REPASSE);
    }

    /**
     * @description Called from RepasseTriggerHandler.afterUpdate.
     *              When NomeSintese__c changes on Repasse__c, dispatches the same
     *              communicator phase-transition flow used by RepasseStatus inserts.
     */
    public static void sendRepassePhaseMessagesFromRepasseUpdate(
        List<Repasse__c> newList,
        Map<Id, Repasse__c> oldMap
    ) {
        if (newList == null || newList.isEmpty()) return;
        List<RepasseStatus__c> syntheticStatuses = new List<RepasseStatus__c>();
        for (Repasse__c repasse : newList) {
            Repasse__c prev = oldMap != null ? oldMap.get(repasse.Id) : null;
            if (prev == null) continue;
            Boolean sinteseChanged = repasse.Sintese__c != prev.Sintese__c;
            Boolean nomeSinteseChanged = repasse.NomeSintese__c != prev.NomeSintese__c;
            Boolean nomeFaseChanged = repasse.NomeFase__c != prev.NomeFase__c;
            if (!sinteseChanged && !nomeSinteseChanged && !nomeFaseChanged) continue;
            syntheticStatuses.add(new RepasseStatus__c(Repasse__c = repasse.Id));
        }
        if (syntheticStatuses.isEmpty()) return;
        sendRepasseStatusMessages(syntheticStatuses);
    }

    /**
     * @description Called from SinteseTriggerHandler.afterUpdate.
     *              When Sintese__c.Name changes, notify communicator transitions for
     *              every Repasse__c currently linked to those synthesis records.
     */
    public static void sendRepassePhaseMessagesFromSinteseNameChange(
        List<Sintese__c> newList,
        Map<Id, Sintese__c> oldMap
    ) {
        if (newList == null || newList.isEmpty()) return;

        Set<Id> changedSinteseIds = new Set<Id>();
        for (Sintese__c sintese : newList) {
            Sintese__c prev = oldMap != null ? oldMap.get(sintese.Id) : null;
            if (prev == null) continue;
            if (sintese.Name == prev.Name) continue;
            changedSinteseIds.add(sintese.Id);
        }
        if (changedSinteseIds.isEmpty()) return;

        List<RepasseStatus__c> syntheticStatuses = new List<RepasseStatus__c>();
        for (Repasse__c repasse : [
            SELECT Id
            FROM Repasse__c
            WHERE Sintese__c IN :changedSinteseIds
            AND Oportunidade__c != null
        ]) {
            syntheticStatuses.add(new RepasseStatus__c(Repasse__c = repasse.Id));
        }
        if (syntheticStatuses.isEmpty()) return;
        sendRepasseStatusMessages(syntheticStatuses);
    }

    // ─────────────────────────────────────────
    // Private — thread lookup
    // ─────────────────────────────────────────

    private static Boolean isRepasseMacroPhase(String stageName) {
        if (String.isBlank(stageName)) return false;
        return REPASSE_MACRO_PHASES.contains(stageName.trim());
    }

    private static Map<Id, Id> findLatestActiveThreadByOppId(Set<Id> oppIds) {
        Map<Id, Id> result = new Map<Id, Id>();
        if (oppIds.isEmpty()) return result;
        for (CommunicatorThread__c t : [
            SELECT Id, RecordId__c
            FROM CommunicatorThread__c
            WHERE RecordId__c IN :oppIds
            AND   Status__c  != 'Archived'
            ORDER BY LastMessageAt__c DESC NULLS LAST
        ]) {
            if (!result.containsKey(t.RecordId__c)) result.put(t.RecordId__c, t.Id);
        }
        return result;
    }

    private static Map<Id, Id> findThreadByOppIdAndCurrentStage(Set<Id> oppIds, Map<Id, String> oppToStage) {
        Map<Id, Id> result   = new Map<Id, Id>();
        if (oppIds.isEmpty()) return result;

        Map<String, Id> keyToThread = new Map<String, Id>();
        for (CommunicatorThread__c t : [
            SELECT Id, RecordId__c, Stage__c
            FROM CommunicatorThread__c
            WHERE RecordId__c IN :oppIds AND Status__c != 'Archived'
            ORDER BY LastMessageAt__c DESC NULLS LAST
        ]) {
            String key = (String) t.RecordId__c + '_' + (t.Stage__c != null ? t.Stage__c : '');
            if (!keyToThread.containsKey(key)) keyToThread.put(key, t.Id);
            if (!result.containsKey(t.RecordId__c)) result.put(t.RecordId__c, t.Id); // fallback: latest
        }
        // Override fallback with stage-specific thread where available
        for (Id oppId : oppToStage.keySet()) {
            String stage = oppToStage.get(oppId);
            String key   = (String) oppId + '_' + (stage != null ? stage : '');
            if (keyToThread.containsKey(key)) result.put(oppId, keyToThread.get(key));
        }
        return result;
    }

    private static Map<Id, Id> findOrCreateThreadByOppIdAndStage(Map<Id, String> oppIdToStage) {
        Map<Id, Id> result = new Map<Id, Id>();
        if (oppIdToStage.isEmpty()) return result;

        Set<Id> oppIds = oppIdToStage.keySet();

        Map<String, Id> keyToThreadId = new Map<String, Id>();
        for (CommunicatorThread__c t : [
            SELECT Id, RecordId__c, Stage__c
            FROM CommunicatorThread__c
            WHERE RecordId__c IN :oppIds
            AND   Status__c  != 'Archived'
        ]) {
            String key = (String) t.RecordId__c + '_' + (t.Stage__c != null ? t.Stage__c : '');
            if (!keyToThreadId.containsKey(key)) keyToThreadId.put(key, t.Id);
        }

        List<CommunicatorThread__c> toCreate = new List<CommunicatorThread__c>();
        Map<Id, CommunicatorThread__c> oppToNewThread = new Map<Id, CommunicatorThread__c>();

        for (Id oppId : oppIdToStage.keySet()) {
            String stage = oppIdToStage.get(oppId);
            String key   = (String) oppId + '_' + (stage != null ? stage : '');
            if (keyToThreadId.containsKey(key)) {
                result.put(oppId, keyToThreadId.get(key));
            } else {
                CommunicatorThread__c t = new CommunicatorThread__c(
                    RecordId__c   = oppId,
                    RecordType__c = 'Opportunity',
                    Stage__c      = stage,
                    Status__c     = 'Active'
                );
                toCreate.add(t);
                oppToNewThread.put(oppId, t);
            }
        }

        if (!toCreate.isEmpty()) {
            insert toCreate;
            for (Id oppId : oppToNewThread.keySet()) {
                result.put(oppId, oppToNewThread.get(oppId).Id);
            }
        }

        return result;
    }

    // ─────────────────────────────────────────
    // Private — message insertion
    // ─────────────────────────────────────────

    private static void dispatchSystemMessages(Map<Id, String> threadToBody, String eventType) {
        threadToBody = CommunicatorSystemEventService.filterDuplicateEvents(threadToBody);
        if (threadToBody == null || threadToBody.isEmpty()) return;
        if (CommunicatorConfigService.useChatterSystemEvents()) {
            Map<Id, Id> threadToFeedItemId = CommunicatorSystemEventService.publishEvents(threadToBody, eventType);
            CommunicatorNotificationService.notifySystemEventsBulk(threadToFeedItemId, threadToBody);
            return;
        }
        Map<Id, Id> threadToMsgId = insertSystemMessages(threadToBody);
        CommunicatorNotificationService.notifyParticipantsBulk(threadToMsgId);
    }

    private static Map<Id, Id> insertSystemMessages(Map<Id, String> threadToBody) {
        Map<Id, Id> threadToMsgId = new Map<Id, Id>();
        if (threadToBody.isEmpty()) return threadToMsgId;

        // Query threads to resolve RecordId__c, RecordType__c and Stage__c for status snapshot
        Map<Id, CommunicatorThread__c> threadById = new Map<Id, CommunicatorThread__c>([
            SELECT Id, RecordId__c, RecordType__c, Stage__c
            FROM CommunicatorThread__c
            WHERE Id IN :threadToBody.keySet()
        ]);

        // Only query the live record status for threads that do NOT have Stage__c set.
        // Phase-change threads always carry Stage__c, which is the authoritative status
        // for that thread. Querying the live Opportunity would return the new stage for
        // both the "Saindo de X" and "Entrando em Y" messages — which is incorrect.
        Map<String, Set<Id>> idsByType = new Map<String, Set<Id>>();
        for (CommunicatorThread__c t : threadById.values()) {
            if (t.RecordId__c == null || String.isBlank(t.RecordType__c)) continue;
            if (String.isNotBlank(t.Stage__c)) continue; // stage already known — skip live query
            if (!idsByType.containsKey(t.RecordType__c)) idsByType.put(t.RecordType__c, new Set<Id>());
            idsByType.get(t.RecordType__c).add(t.RecordId__c);
        }

        // Batch-query the current status field per object type — one SOQL per type
        Map<Id, String> recordStatusById = new Map<Id, String>();
        for (String objType : idsByType.keySet()) {
            String statusField = CommunicatorConfigService.getStatusFieldName(objType);
            if (String.isBlank(statusField)) continue;
            try {
                Set<Id> ids = idsByType.get(objType);
                List<SObject> recs = Database.query(
                    'SELECT Id, ' + statusField + ' FROM ' + objType + ' WHERE Id IN :ids'
                );
                for (SObject rec : recs) {
                    Object val = rec.get(statusField);
                    recordStatusById.put(rec.Id, val != null ? String.valueOf(val) : null);
                }
            } catch (Exception ex) {
                System.debug(LoggingLevel.WARN,
                    'CommunicatorSystemMessageService.insertSystemMessages: status query failed for '
                    + objType + ' — ' + ex.getMessage());
            }
        }

        DateTime now = System.now();
        List<CommunicatorMessage__c> toInsert = new List<CommunicatorMessage__c>();
        for (Id threadId : threadToBody.keySet()) {
            String body = threadToBody.get(threadId);
            if (String.isBlank(body)) continue;
            CommunicatorThread__c thread = threadById.get(threadId);
            // Prefer Stage__c (exact phase of this thread) over the live record status
            String recordStatus = null;
            if (thread != null) {
                recordStatus = String.isNotBlank(thread.Stage__c)
                    ? thread.Stage__c
                    : (thread.RecordId__c != null ? recordStatusById.get(thread.RecordId__c) : null);
            }
            toInsert.add(new CommunicatorMessage__c(
                Thread__c          = threadId,
                Body__c            = body,
                SearchBody__c      = body.length() > 255 ? body.substring(0, 255) : body,
                IsSystemMessage__c = true,
                SentAt__c          = now,
                Status__c          = 'Sent',
                RecordStatus__c    = recordStatus
            ));
        }
        if (toInsert.isEmpty()) return threadToMsgId;

        insert toInsert;

        for (CommunicatorMessage__c msg : toInsert) {
            threadToMsgId.put(msg.Thread__c, msg.Id);
        }

        List<CommunicatorThread__c> threadsToUpdate = new List<CommunicatorThread__c>();
        for (Id threadId : threadToBody.keySet()) {
            threadsToUpdate.add(new CommunicatorThread__c(Id = threadId, LastMessageAt__c = now));
        }
        update threadsToUpdate;

        return threadToMsgId;
    }

    // ─────────────────────────────────────────
    // Private — message body builders
    // ─────────────────────────────────────────

    private static String buildARReprovadoBody(String motivo, List<DocumentoChecklist__c> docs) {
        String body = 'Análise de renda finalizada com reprovação.';
        if (String.isNotBlank(motivo)) body += '\nMotivo: ' + motivo;
        if (docs == null || docs.isEmpty()) return body;
        body += '\n\nDocumentos recusados:';
        for (DocumentoChecklist__c doc : docs) {
            String docName = String.isNotBlank(doc.IdDocumento__c) ? doc.IdDocumento__c : doc.Name;
            String status  = String.isNotBlank(doc.StatusAprovacao__c) ? ' (' + doc.StatusAprovacao__c + ')' : '';
            String obs     = String.isNotBlank(doc.Observacoes__c) ? ' — ' + doc.Observacoes__c : '';
            body += '\n• ' + docName + status + obs;
        }
        return body;
    }

    private static String buildACReprovadoBody(String motivo, List<DocumentoChecklist__c> docs) {
        String body = 'Análise de crédito finalizada com reprovação.';
        if (String.isNotBlank(motivo)) body += '\nMotivo: ' + motivo;
        if (docs == null || docs.isEmpty()) return body;
        body += '\n\nDocumentos recusados:';
        for (DocumentoChecklist__c doc : docs) {
            String docName = String.isNotBlank(doc.IdDocumento__c) ? doc.IdDocumento__c : doc.Name;
            String status  = String.isNotBlank(doc.StatusAprovacao__c) ? ' (' + doc.StatusAprovacao__c + ')' : '';
            String obs     = String.isNotBlank(doc.Observacoes__c) ? ' — ' + doc.Observacoes__c : '';
            body += '\n• ' + docName + status + obs;
        }
        return body;
    }

    private static String buildARProgressBody(String status) {
        if (status == 'Não iniciado') return 'Análise de renda aguardando início.';
        if (status == 'Em análise')   return 'Análise de renda iniciada.';
        if (status == 'Na Agência')   return 'Análise de renda encaminhada para agência.';
        if (status == 'Vencido')      return 'Análise de renda vencida.';
        return null;
    }

    private static String buildACProgressBody(String status) {
        if (status == 'Não iniciado') return 'Análise de crédito aguardando início.';
        if (status == 'Em análise')   return 'Análise de crédito iniciada.';
        if (status == 'Na Agência')   return 'Análise de crédito encaminhada para agência.';
        if (status == 'Vencido')      return 'Análise de crédito vencida.';
        return null;
    }

    private static String buildABApprovalBody(AprovacaoBancaria__c ab, String fgts3anos) {
        String header = (ab.StatusAprovacaoBancaria__c == 'Aprovada com Pendências')
            ? 'Aprovação bancária aprovada com pendências.'
            : 'Aprovação bancária aprovada com sucesso.';

        String body = header;
        if (String.isNotBlank(ab.ModalidadeFinanciamento__c)) {
            body += '\nModalidade: ' + ab.ModalidadeFinanciamento__c;
        }
        if (ab.ValorFinanciamento__c != null) {
            body += '\nValor do financiamento: R$ ' + fmtDecimal(ab.ValorFinanciamento__c);
        }
        if (ab.ValorParcela__c != null) {
            body += '\nValor da parcela: R$ ' + fmtDecimal(ab.ValorParcela__c);
        }
        Decimal perAprovacaoParcela = getDecimalFieldIfAvailable(ab, 'PerAprovacaoParcela__c');
        if (perAprovacaoParcela != null) {
            body += '\n% da Parcela aprovada: ' + fmtDecimal(perAprovacaoParcela) + '%';
        }
        if (ab.LTV__c != null) {
            body += '\nLTV: ' + fmtDecimal(ab.LTV__c) + '%';
        }
        if (ab.ValorSubsidio__c != null && ab.ValorSubsidio__c > 0) {
            body += '\nSubsídio: R$ ' + fmtDecimal(ab.ValorSubsidio__c);
        }
        if (String.isNotBlank(fgts3anos)) {
            body += '\nFGTS 3 anos: ' + fgts3anos;
        }
        if (String.isNotBlank(ab.Observacoes__c)) {
            body += '\nObservações: ' + ab.Observacoes__c;
        }
        return body;
    }

    private static String buildABReprovadoBody(AprovacaoBancaria__c ab) {
        String body = 'Aprovação bancária reprovada.';
        if (String.isNotBlank(ab.Observacoes__c)) body += '\nObservações: ' + ab.Observacoes__c;
        return body;
    }

    private static String fmtDecimal(Decimal val) {
        if (val == null) return '0,00';
        String plain = val.setScale(2).toPlainString();
        List<String> parts = plain.split('\\.');
        String intPart = parts[0];
        String decPart = parts.size() > 1 ? parts[1] : '00';
        String result = '';
        Integer len = intPart.length();
        for (Integer i = 0; i < len; i++) {
            if (i > 0 && Math.mod(len - i, 3) == 0) result += '.';
            result += intPart.substring(i, i + 1);
        }
        return result + ',' + decPart;
    }

    private static Decimal getDecimalFieldIfAvailable(SObject record, String fieldApiName) {
        if (record == null || String.isBlank(fieldApiName)) return null;

        Map<String, Schema.SObjectField> fieldMap = record.getSObjectType().getDescribe().fields.getMap();
        if (!fieldMap.containsKey(fieldApiName)) return null;

        Object value = record.get(fieldApiName);
        if (value == null) return null;

        try {
            return (Decimal) value;
        } catch (Exception e) {
            return null;
        }
    }
}