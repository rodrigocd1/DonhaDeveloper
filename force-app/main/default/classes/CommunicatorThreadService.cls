/**
 * @description Service responsible for CommunicatorThread__c business logic.
 *              Thread is generic — it can be linked to any SObject via RecordId__c.
 */
public with sharing class CommunicatorThreadService {
    private class NotificationAccessVolumeException extends Exception {}
    @TestVisible private static Boolean forceSalesforcePlatformUserForTest;
    @TestVisible private static Boolean useSalesforcePlatformOverrideForTest;
    @TestVisible private static Set<Id> forceSalesforcePlatformPresenceUsersForTest;
    @TestVisible private static Boolean forceEnsureRepasseAccessExceptionForTest;
    @TestVisible private static Map<Id, CommunicatorThread__c> notificationThreadByIdCache = new Map<Id, CommunicatorThread__c>();
    @TestVisible private static Map<Id, Set<Id>> mentionedGroupIdsByThreadIdCache = new Map<Id, Set<Id>>();
    @TestVisible private static Map<Id, ThreadNotificationContext> notificationContextByThreadIdCache = new Map<Id, ThreadNotificationContext>();
    @TestVisible private static Map<Id, Set<Id>> queueHierarchyByRootQueueIdCache = new Map<Id, Set<Id>>();
    @TestVisible private static Map<Id, Set<Id>> arQueueEligibleUsersByRootQueueIdCache = new Map<Id, Set<Id>>();
    @TestVisible private static Map<Id, Id> arOwnerQueueByApuracaoIdCache = new Map<Id, Id>();
    @TestVisible private static Map<Id, OpportunityNotificationContext> opportunityNotificationContextByOppId = new Map<Id, OpportunityNotificationContext>();
    @TestVisible private static Map<Id, Boolean> hasAprovacaoBancariaByAnaliseCreditoId = new Map<Id, Boolean>();
    @TestVisible private static Map<Id, Repasse__c> repasseByOpportunityIdForNotificationCache = new Map<Id, Repasse__c>();
    @TestVisible private static Map<Id, Repasse__c> notificationRepasseByIdCache = new Map<Id, Repasse__c>();
    @TestVisible private static Map<Id, Set<Id>> assessoriaIdsByUserIdCache = new Map<Id, Set<Id>>();
    @TestVisible private static Map<Id, Set<Id>> queueIdsByUserIdCache = new Map<Id, Set<Id>>();
    @TestVisible private static Map<Id, Id> userRoleIdByUserIdCache = new Map<Id, Id>();
    @TestVisible private static Map<Id, Set<Id>> roleGroupIdsByRoleIdCache = new Map<Id, Set<Id>>();
    @TestVisible private static Map<Id, List<GroupMember>> parentGroupMembershipsByMemberIdCache = new Map<Id, List<GroupMember>>();
    // Test seam: AnaliseFinanceira Id -> queue Id used only by tests.
    @TestVisible private static Map<Id, Id> testAnaliseFinanceiraOwnerQueueIdsByAnaliseId;
    @TestVisible private static Boolean isSalesforcePlatformUserCache;
    @TestVisible private static Boolean isSalesforcePlatformUserCacheInitialized = false;
    @TestVisible private static Set<Id> currentUserQueueIdsCache;
    @TestVisible private static Boolean currentUserQueueIdsCacheInitialized = false;
    @TestVisible private static Set<Id> currentUserAssessoriaIdsCache;
    @TestVisible private static Boolean currentUserAssessoriaIdsCacheInitialized = false;
    @TestVisible private static Set<Id> groupMentionedThreadIdsCache;
    @TestVisible private static Boolean groupMentionedThreadIdsCacheInitialized = false;
    // Test hook: simulate opp ids that are invisible to the with-sharing query
    @TestVisible private static Set<Id> simulateInaccessibleOppIdsForTest;

    /**
     * @description Returns the existing active thread for a given record Id,
     *              or creates a new one if none exists.
     * @param recordId   Id of any SObject record (Opportunity, Account, Case, etc.)
     * @param objectType API name of the SObject (e.g. 'Opportunity'). Used for reference only.
     * @return CommunicatorThread__c record.
     */
    /**
     * @description Returns the existing active thread for a given record and its
     *              current stage, or creates a new one if none exists for that pair.
     *              One thread per (RecordId, Stage) combination — if the record
     *              returns to a previous stage, the original thread is reused.
     */
    public static CommunicatorThread__c getOrCreateThread(String recordId, String objectType) {
        if (String.isBlank(recordId)) {
            throw new CommunicatorException('Record ID cannot be blank.');
        }

        // Resolve object type
        String resolvedType = objectType;
        if (String.isBlank(resolvedType)) {
            try {
                Id sfId = (Id) recordId;
                resolvedType = sfId.getSObjectType().getDescribe().getName();
            } catch (Exception e) { resolvedType = ''; }
        }

        // Repasse usa o chat da Opportunity vinculada quando existir.
        // Sem Opportunity vinculada, mantém o contexto do próprio Repasse.
        if (resolvedType == 'Repasse__c') {
            String resolvedOpportunityId = resolveOpportunityIdIfRepasse(recordId);
            if (!String.isBlank(resolvedOpportunityId) && resolvedOpportunityId != recordId) {
                recordId = resolvedOpportunityId;
                resolvedType = 'Opportunity';
            }
        }

        // Se a Opportunity tem um Repasse ativo, roteia para a thread da fase atual do Repasse
        if (resolvedType == 'Opportunity' || String.isBlank(resolvedType)) {
            String repassePhase = CommunicatorRepassePhaseHelper.getRepasseMacroPhaseByOppId((Id) recordId);
            if (String.isNotBlank(repassePhase)) {
                try {
                    Id threadId = ensureThreadForRepassePhase((Id) recordId, repassePhase);
                    return [
                        SELECT Id, Name, RecordId__c, RecordType__c, Status__c, Stage__c,
                               SubStatus__c, Reason__c, ExternalId__c, LastMessageAt__c, UnreadCount__c
                        FROM   CommunicatorThread__c
                        WHERE  Id = :threadId
                        LIMIT  1
                    ];
                } catch (CommunicatorException accessEx) {
                    // Mentioned participants can still reuse the existing Repasse thread
                    // even when they don't have direct sharing on the Opportunity.
                }
            }
            // Fallback for mentioned users without record sharing:
            // if we can't resolve the current Repasse phase by access context,
            // reuse an existing Repasse-phase thread for this Opportunity.
            CommunicatorThread__c existingRepasseThread = getLatestRepassePhaseThreadByRecordId(recordId);
            if (existingRepasseThread != null) {
                return existingRepasseThread;
            }
        }

        if (!canAccessRecordOrParticipatesInThread(recordId)) {
            throw new CommunicatorException('Record not found or not accessible.');
        }

        // Resolve current stage of the linked record
        String currentStage = CommunicatorRecordStatusService.getRecordStatus(recordId, resolvedType);

        // Find existing thread for this (record, stage) pair
        List<CommunicatorThread__c> threads;
        if (String.isNotBlank(currentStage)) {
            threads = [
                SELECT Id, Name, RecordId__c, RecordType__c, Status__c, Stage__c,
                       SubStatus__c, Reason__c, ExternalId__c,
                       LastMessageAt__c, UnreadCount__c
                FROM   CommunicatorThread__c
                WHERE  RecordId__c = :recordId
                AND    Stage__c    = :currentStage
                AND    Status__c  != 'Archived'
                LIMIT  1
            ];
        } else {
            // No stage configured — find any thread for this record with no stage
            threads = [
                SELECT Id, Name, RecordId__c, RecordType__c, Status__c, Stage__c,
                       SubStatus__c, Reason__c, ExternalId__c,
                       LastMessageAt__c, UnreadCount__c
                FROM   CommunicatorThread__c
                WHERE  RecordId__c = :recordId
                AND    Stage__c    = null
                AND    Status__c  != 'Archived'
                LIMIT  1
            ];
        }

        if (!threads.isEmpty()) {
            return threads[0];
        }

        return createThread(recordId, resolvedType, currentStage);
    }

    /**
     * @description Ensures an active thread exists for an Opportunity + Repasse macro-phase.
     * @param opportunityId Opportunity Id.
     * @param macroPhase Repasse macro-phase label.
     * @return Existing or newly created thread Id.
     */
    public static Id ensureThreadForRepassePhase(Id opportunityId, String macroPhase) {
        if (opportunityId == null || String.isBlank(macroPhase)) return null;

        String stage = macroPhase.trim();
        if (Test.isRunningTest() && forceEnsureRepasseAccessExceptionForTest == true) {
            throw new CommunicatorException('Record not found or not accessible.');
        }
        validateRecordAccess(String.valueOf(opportunityId));

        // First, try exact match.
        List<CommunicatorThread__c> existing = [
            SELECT Id, Stage__c
            FROM   CommunicatorThread__c
            WHERE  RecordId__c = :opportunityId
            AND    Stage__c    = :stage
            AND    Status__c  != 'Archived'
            LIMIT  1
        ];
        if (!existing.isEmpty()) return existing[0].Id;

        // Fallback: match by normalized macro-phase to avoid duplicates caused by
        // accent/casing variants (e.g. "Formulário" vs "Formulario").
        String normalizedTargetStage = normalizeCommunicatorStage(stage);
        for (CommunicatorThread__c threadRecord : [
            SELECT Id, Stage__c
            FROM   CommunicatorThread__c
            WHERE  RecordId__c = :opportunityId
            AND    Status__c  != 'Archived'
            ORDER  BY LastMessageAt__c DESC NULLS LAST, CreatedDate DESC
        ]) {
            if (String.isBlank(threadRecord.Stage__c)) continue;
            if (normalizeCommunicatorStage(threadRecord.Stage__c) == normalizedTargetStage) {
                return threadRecord.Id;
            }
        }

        return createThread(String.valueOf(opportunityId), 'Opportunity', stage).Id;
    }

    /**
     * @description Lista oportunidades acessíveis ao usuário e enriquece com dados da thread (se existir).
     *              Se não existir thread para a oportunidade, retorna o item com threadId vazio.
     * @param pageSize  Número de registros por página.
     * @param offsetVal Offset (zero-based).
     * @param filter    'all' | 'read' | 'unread'
     * @param keyword   Termo opcional (nome/fase).
     */
    public static List<CommunicatorDTOs.ThreadListItemDTO> getOpportunityChatList(
        Integer pageSize, Integer offsetVal, String filter, String keyword
    ) {
        Id      userId = UserInfo.getUserId();
        Integer sz     = (pageSize  != null && pageSize  > 0) ? pageSize  : 20;
        Integer off    = (offsetVal != null && offsetVal >= 0) ? offsetVal : 0;
        String  kw     = normalizeKeyword(keyword);
        Set<String> cpfSearchValues = buildCpfSearchValues(kw);

        String likeKw = buildContainsLikePattern(kw);
        Set<Id> visibleAssessoriaIds = getVisibleAssessoriaIdsForCurrentUser();
        // Without keyword: show only threads the user has interacted with or was mentioned in.
        // The participant block below populates the result via participantOppById.
        // With keyword: search all accessible records so the user can discover and join new threads.
        List<Opportunity> opps = new List<Opportunity>();
        if (!String.isBlank(kw)) {
            if (visibleAssessoriaIds != null && !visibleAssessoriaIds.isEmpty()) {
                opps = [
                    SELECT Id, Name, StageName, LastModifiedDate
                    FROM Opportunity
                    WHERE (Name LIKE :likeKw OR StageName LIKE :likeKw)
                    AND AssessoriaCredito__c IN :visibleAssessoriaIds
                    ORDER BY LastModifiedDate DESC
                    LIMIT :sz OFFSET :off
                ];
            } else {
                opps = [
                    SELECT Id, Name, StageName, LastModifiedDate
                    FROM Opportunity
                    WHERE Name LIKE :likeKw OR StageName LIKE :likeKw
                    ORDER BY LastModifiedDate DESC
                    LIMIT :sz OFFSET :off
                ];
            }
        }

        // Repasse aparece no mesmo campo de busca; ele usa o chat da Opportunity (Oportunidade__c)
        List<Repasse__c> repasses = new List<Repasse__c>();
        List<Opportunity> visibleRepasseOpps = new List<Opportunity>();
        Set<Id> repasseCandidateOppIds = new Set<Id>();
        if (!String.isBlank(kw)) {
            repasseCandidateOppIds = CommunicatorRepasseService.getCandidateOpportunityIdsByKeyword(
                kw,
                sz,
                visibleAssessoriaIds
            );
            Set<Id> additionalKeywordOppIds = getAdditionalOpportunityIdsByKeyword(kw, sz, cpfSearchValues);
            Set<Id> candidateOppIds = new Set<Id>();
            candidateOppIds.addAll(repasseCandidateOppIds);
            candidateOppIds.addAll(additionalKeywordOppIds);
            if (!candidateOppIds.isEmpty()) {
                Map<Id, Opportunity> visibleCandidateOppById = new Map<Id, Opportunity>(
                    CommunicatorOpportunityAccessService.getVisibleOpportunitiesByIds(candidateOppIds)
                );
                Map<Id, Opportunity> oppById = new Map<Id, Opportunity>(opps);
                for (Id repasseOpportunityId : repasseCandidateOppIds) {
                    if (visibleCandidateOppById.containsKey(repasseOpportunityId)) {
                        visibleRepasseOpps.add(visibleCandidateOppById.get(repasseOpportunityId));
                    }
                }
                for (Opportunity candidateOpportunity : visibleCandidateOppById.values()) {
                    if (candidateOpportunity == null || candidateOpportunity.Id == null) continue;
                    if (oppById.containsKey(candidateOpportunity.Id)) continue;
                    oppById.put(candidateOpportunity.Id, candidateOpportunity);
                    opps.add(candidateOpportunity);
                }
                repasses = CommunicatorRepasseService.getRepassesByOpportunityIds(
                    new Map<Id, Opportunity>(visibleRepasseOpps).keySet(),
                    kw,
                    sz,
                    visibleAssessoriaIds
                );
            }
        }

        Set<Id> oppIds = new Set<Id>();
        Map<Id, String> currentStageByOppId = new Map<Id, String>();
        for (Opportunity o : opps) {
            oppIds.add(o.Id);
            currentStageByOppId.put(o.Id, o.StageName);
        }
        for (Opportunity visibleRepasseOpp : visibleRepasseOpps) {
            if (visibleRepasseOpp == null || visibleRepasseOpp.Id == null) continue;
            oppIds.add(visibleRepasseOpp.Id);
            if (!currentStageByOppId.containsKey(visibleRepasseOpp.Id)) {
                currentStageByOppId.put(visibleRepasseOpp.Id, visibleRepasseOpp.StageName);
            }
        }

        // Also include Opportunities from threads where the user is an active participant
        // but the Opportunity may not be directly accessible via sharing (e.g., mentioned users).
        // Uses CommunicatorOpportunityDataService (without sharing) so mentioned users can always
        // see threads they were added to, regardless of record-level access on the Opportunity.
        Map<Id, Opportunity> participantOppById = new Map<Id, Opportunity>();
        Set<Id> participantThreadIds = new Set<Id>();
        for (CommunicatorParticipant__c p : [
            SELECT Thread__c FROM CommunicatorParticipant__c
            WHERE User__c = :userId AND IsActive__c = true
        ]) {
            participantThreadIds.add(p.Thread__c);
        }
        if (!participantThreadIds.isEmpty()) {
            Set<Id> participantOppIds = new Set<Id>();
            for (CommunicatorThread__c pt : [
                SELECT RecordId__c FROM CommunicatorThread__c
                WHERE Id IN :participantThreadIds
                AND   RecordType__c = 'Opportunity'
                AND   Status__c    != 'Archived'
            ]) {
                try {
                    Id recId = (Id) pt.RecordId__c;
                    if (recId != null && String.valueOf(recId).startsWith('006')) {
                        participantOppIds.add(recId);
                    }
                } catch (Exception e) { /* skip invalid */ }
            }
            if (!participantOppIds.isEmpty()) {
                Set<Id> missingIds = new Set<Id>();
                for (Id pid : participantOppIds) {
                    if (!oppIds.contains(pid)) missingIds.add(pid);
                }
                if (!missingIds.isEmpty()) {
                    for (Opportunity po : CommunicatorOpportunityDataService.getOpportunitiesByIds(missingIds)) {
                        oppIds.add(po.Id);
                        participantOppById.put(po.Id, po);
                        if (!currentStageByOppId.containsKey(po.Id)) {
                            currentStageByOppId.put(po.Id, po.StageName);
                        }
                    }
                }
            }
        }

        if (isCurrentUserSalesforcePlatform()) {
            oppIds = getEligibleOpportunityIdsForSalesforcePlatform(oppIds);
            Set<Id> mentionOppIds = getMentionAccessibleOpportunityIdsForCurrentUser();
            oppIds.addAll(mentionOppIds);
            for (Opportunity mentionOpportunity : CommunicatorOpportunityDataService.getOpportunitiesByIds(mentionOppIds)) {
                if (!currentStageByOppId.containsKey(mentionOpportunity.Id)) {
                    currentStageByOppId.put(mentionOpportunity.Id, mentionOpportunity.StageName);
                }
            }
            Set<Id> eligibleThreadIds = getEligibleThreadIdsForSalesforcePlatform();
            if (!eligibleThreadIds.isEmpty()) {
                Set<Id> eligibleOppIdsFromThreads = new Set<Id>();
                for (CommunicatorThread__c eligibleThread : [
                    SELECT RecordId__c
                    FROM CommunicatorThread__c
                    WHERE Id IN :eligibleThreadIds
                    AND Status__c != 'Archived'
                ]) {
                    try {
                        Id opportunityId = (Id) eligibleThread.RecordId__c;
                        if (opportunityId != null && String.valueOf(opportunityId).startsWith('006')) {
                            eligibleOppIdsFromThreads.add(opportunityId);
                        }
                    } catch (Exception e) { /* skip invalid id */ }
                }
                oppIds.addAll(eligibleOppIdsFromThreads);
                for (Opportunity eligibleOpportunity : CommunicatorOpportunityDataService.getOpportunitiesByIds(eligibleOppIdsFromThreads)) {
                    if (!currentStageByOppId.containsKey(eligibleOpportunity.Id)) {
                        currentStageByOppId.put(eligibleOpportunity.Id, eligibleOpportunity.StageName);
                    }
                }
            }
        }

        if (isCurrentUserSalesforcePlatform() && opps.isEmpty()) {
            List<Opportunity> eligibleOpps = CommunicatorOpportunityDataService.getOpportunitiesByIds(oppIds);
            for (Opportunity eligibleOpportunity : eligibleOpps) {
                if (eligibleOpportunity == null || eligibleOpportunity.Id == null) continue;
                opps.add(eligibleOpportunity);
                if (!currentStageByOppId.containsKey(eligibleOpportunity.Id)) {
                    currentStageByOppId.put(eligibleOpportunity.Id, eligibleOpportunity.StageName);
                }
            }
        }
        if (!String.isBlank(kw)) {
            if (isCurrentUserSalesforcePlatform()) {
                oppIds = getVisibleOpportunityCardIdsForCurrentUser(oppIds);
                if (oppIds.isEmpty()) return new List<CommunicatorDTOs.ThreadListItemDTO>();
                opps = filterOpportunitiesByIds(opps, oppIds);
            }
            Set<Id> matchedOpportunityIds = getMatchedOpportunityIdsByKeyword(
                oppIds,
                kw,
                repasseCandidateOppIds,
                cpfSearchValues
            );
            if (matchedOpportunityIds.isEmpty()) {
                return new List<CommunicatorDTOs.ThreadListItemDTO>();
            }
            oppIds.retainAll(matchedOpportunityIds);
            opps = filterOpportunitiesByIds(opps, matchedOpportunityIds);
            ensureOpportunitiesLoaded(opps, oppIds, currentStageByOppId);
        }
        if (oppIds.isEmpty()) return new List<CommunicatorDTOs.ThreadListItemDTO>();

        Map<Id, Repasse__c> latestRepasseByOppId =
            CommunicatorRepasseService.getLatestRepassesByOpportunityIds(oppIds, visibleAssessoriaIds);
        Map<Id, Boolean> hasRepasseByOppId = new Map<Id, Boolean>();
        Map<Id, String> repasseMacroPhaseByOppId = new Map<Id, String>();
        Map<Id, String> effectiveCurrentStageByOppId = new Map<Id, String>();
        for (Id oppId : oppIds) {
            Repasse__c latestRepasse = latestRepasseByOppId.get(oppId);
            if (latestRepasse != null) {
                hasRepasseByOppId.put(oppId, true);
                String repasseSinteseName = CommunicatorRepassePhaseHelper.getRepasseSinteseName(latestRepasse);
                String repasseMacroPhase = CommunicatorRepassePhaseHelper.getMacroPhase(repasseSinteseName);
                if (String.isNotBlank(repasseMacroPhase)) {
                    repasseMacroPhaseByOppId.put(oppId, repasseMacroPhase);
                }
            }
            effectiveCurrentStageByOppId.put(
                oppId,
                repasseMacroPhaseByOppId.containsKey(oppId)
                    ? repasseMacroPhaseByOppId.get(oppId)
                    : currentStageByOppId.get(oppId)
            );
        }

        // Busca threads ativas para essas opportunities
        List<CommunicatorThread__c> threads = [
            SELECT Id, Name, RecordId__c, RecordType__c, Stage__c, SubStatus__c, Status__c, LastMessageAt__c
            FROM CommunicatorThread__c
            WHERE RecordId__c IN :oppIds
            AND Status__c != 'Archived'
            ORDER BY LastMessageAt__c DESC NULLS LAST
        ];

        Map<Id, CommunicatorThread__c> latestByOpp = new Map<Id, CommunicatorThread__c>();
        Map<Id, CommunicatorThread__c> stageMatchByOpp = new Map<Id, CommunicatorThread__c>();
        Map<Id, Set<Id>> allThreadIdsByOpp = new Map<Id, Set<Id>>();
        for (CommunicatorThread__c t : threads) {
            Id rid;
            try { rid = (Id) t.RecordId__c; } catch (Exception e) { continue; }

            if (!allThreadIdsByOpp.containsKey(rid)) allThreadIdsByOpp.put(rid, new Set<Id>());
            allThreadIdsByOpp.get(rid).add(t.Id);

            if (!latestByOpp.containsKey(rid)) latestByOpp.put(rid, t);

            // Use effectiveCurrentStageByOppId so that when an Opportunity has an
            // active repasse, the repasse macro-phase thread (RecordType='Opportunity',
            // Stage=repasse phase) is preferred over the opportunity-phase thread.
            String currentStage = effectiveCurrentStageByOppId.containsKey(rid)
                ? effectiveCurrentStageByOppId.get(rid)
                : currentStageByOppId.get(rid);
            Boolean stageMatches = (String.isBlank(currentStage) && t.Stage__c == null)
                || (String.isNotBlank(currentStage) && t.Stage__c == currentStage);
            if (stageMatches && !stageMatchByOpp.containsKey(rid)) {
                stageMatchByOpp.put(rid, t);
            }
        }

        Map<Id, CommunicatorThread__c> selectedThreadByOpp = new Map<Id, CommunicatorThread__c>();
        for (Id oid : oppIds) {
            CommunicatorThread__c chosen = stageMatchByOpp.containsKey(oid)
                ? stageMatchByOpp.get(oid)
                : latestByOpp.get(oid);
            if (chosen != null) {
                selectedThreadByOpp.put(oid, chosen);
            }
        }

        Map<Id, Id> lastSenderByThreadId = new Map<Id, Id>();
        Set<Id> selectedThreadIds = new Set<Id>();
        for (CommunicatorThread__c selectedThread : selectedThreadByOpp.values()) {
            if (selectedThread != null && selectedThread.Id != null) {
                selectedThreadIds.add(selectedThread.Id);
            }
        }
        if (!selectedThreadIds.isEmpty()) {
            for (CommunicatorMessage__c messageRecord : [
                SELECT Thread__c, Sender__c
                FROM CommunicatorMessage__c
                WHERE Thread__c IN :selectedThreadIds
                ORDER BY SentAt__c DESC
                LIMIT 200
            ]) {
                if (messageRecord.Thread__c == null || messageRecord.Sender__c == null) continue;
                if (!lastSenderByThreadId.containsKey(messageRecord.Thread__c)) {
                    lastSenderByThreadId.put(messageRecord.Thread__c, messageRecord.Sender__c);
                }
            }
        }

        Set<Id> allThreadIds = new Set<Id>();
        for (Set<Id> idsByOpp : allThreadIdsByOpp.values()) {
            allThreadIds.addAll(idsByOpp);
        }

        // Unread por thread (todos os threads do registro)
        Map<Id, Integer> unreadByThread = new Map<Id, Integer>();
        if (!allThreadIds.isEmpty()) {
            for (AggregateResult ar : [
                SELECT Thread__c tid, COUNT(Id) cnt
                FROM   CommunicatorNotification__c
                WHERE  Thread__c    IN :allThreadIds
                AND    Recipient__c = :userId
                AND    IsRead__c    = false
                GROUP  BY Thread__c
            ]) {
                unreadByThread.put((Id) ar.get('tid'), Integer.valueOf(ar.get('cnt')));
            }
        }

        // lastReadAt por thread — MAX(ReadAt__c) das notificações lidas pelo usuário.
        // Só muda quando o usuário lê notificações novas (unread→read); abrir um thread
        // já lido não altera ReadAt__c porque markThreadAsRead retorna cedo se não há
        // notificações pendentes.
        Map<Id, DateTime> lastReadAtByThread = new Map<Id, DateTime>();
        if (!allThreadIds.isEmpty()) {
            for (AggregateResult ar : [
                SELECT Thread__c tid, MAX(ReadAt__c) maxReadAt
                FROM   CommunicatorNotification__c
                WHERE  Thread__c    IN :allThreadIds
                AND    Recipient__c = :userId
                AND    IsRead__c    = true
                GROUP  BY Thread__c
            ]) {
                DateTime readAt = (DateTime) ar.get('maxReadAt');
                if (readAt != null) lastReadAtByThread.put((Id) ar.get('tid'), readAt);
            }
        }

        // Unread agregado por Opportunity (somando Opportunity + Repasse threads)
        Map<Id, Integer> unreadTotalByOpp = new Map<Id, Integer>();
        // lastReadAt agregado por Opportunity (MAX entre todos os threads relacionados)
        Map<Id, DateTime> lastReadAtByOpp = new Map<Id, DateTime>();
        for (Id oppId : oppIds) {
            Integer totalUnread = 0;
            DateTime latestReadAt = null;
            Set<Id> oppThreadIds = allThreadIdsByOpp.get(oppId);
            if (oppThreadIds != null) {
                for (Id tid : oppThreadIds) {
                    totalUnread += unreadByThread.containsKey(tid) ? unreadByThread.get(tid) : 0;
                    DateTime threadReadAt = lastReadAtByThread.get(tid);
                    if (threadReadAt != null && (latestReadAt == null || threadReadAt > latestReadAt)) {
                        latestReadAt = threadReadAt;
                    }
                }
            }
            unreadTotalByOpp.put(oppId, totalUnread);
            if (latestReadAt != null) lastReadAtByOpp.put(oppId, latestReadAt);
        }

        List<CommunicatorDTOs.ThreadListItemDTO> result = new List<CommunicatorDTOs.ThreadListItemDTO>();
        for (Opportunity o : opps) {
            if (!oppIds.contains(o.Id)) continue;
            CommunicatorThread__c t = selectedThreadByOpp.get(o.Id);
            Integer unread = unreadTotalByOpp.containsKey(o.Id) ? unreadTotalByOpp.get(o.Id) : 0;
            Repasse__c latestRepasse = latestRepasseByOppId.get(o.Id);
            Boolean displayAsRepasse = hasRepasseByOppId.containsKey(o.Id);
            String repasseSinteseName = CommunicatorRepassePhaseHelper.getRepasseSinteseName(latestRepasse);

            CommunicatorDTOs.ThreadListItemDTO dto = new CommunicatorDTOs.ThreadListItemDTO();
            dto.threadId      = (t != null) ? t.Id : null;
            dto.threadName    = (t != null) ? t.Name : null;
            dto.recordId      = o.Id;
            dto.recordName    = o.Name;
            if (isCurrentUserSalesforcePlatform() && displayAsRepasse && latestRepasse != null) {
                dto.recordName = latestRepasse.Name;
            }
            dto.recordType    = 'Opportunity';
            dto.hasRepasse    = displayAsRepasse;
            dto.stageName     = (t != null) ? t.Stage__c : null;
            String repasseCurrentPhase = repasseMacroPhaseByOppId.get(o.Id);
            dto.currentStage  = displayAsRepasse && String.isNotBlank(repasseCurrentPhase)
                ? repasseCurrentPhase
                : (displayAsRepasse ? repasseSinteseName : effectiveCurrentStageByOppId.get(o.Id));
            dto.displayStatus = dto.currentStage;
            dto.displayStatusLabel = 'Fase atual:';
            dto.rawRepasseStatus = (displayAsRepasse && latestRepasse != null)
                ? repasseSinteseName
                : null;
            dto.hasRepasse    = hasRepasseByOppId.containsKey(o.Id);
            dto.stageName     = (t != null) ? t.Stage__c : null;
            dto.currentStage  = displayAsRepasse && String.isNotBlank(repasseCurrentPhase)
                ? repasseCurrentPhase
                : (displayAsRepasse ? repasseSinteseName : effectiveCurrentStageByOppId.get(o.Id));
            dto.statusLabel   = (t != null) ? t.SubStatus__c : null;
            dto.lastSenderId  = (t != null && lastSenderByThreadId.containsKey(t.Id))
                ? String.valueOf(lastSenderByThreadId.get(t.Id))
                : null;
            dto.lastMessageAt = (t != null && t.LastMessageAt__c != null)
                ? t.LastMessageAt__c.format('dd/MM/yyyy HH:mm')
                : '';
            dto.unreadCount   = unread;
            dto.isRead        = unread == 0;
            DateTime oppLastReadAt = lastReadAtByOpp.get(o.Id);
            dto.lastReadAt    = (oppLastReadAt != null) ? oppLastReadAt.format('dd/MM/yyyy HH:mm:ss') : '';

            if (filter == 'unread' && unread == 0) continue;
            if (filter == 'read' && unread > 0) continue;
            result.add(dto);
        }

        for (Repasse__c r : repasses) {
            if (r.Oportunidade__c == null || !oppIds.contains(r.Oportunidade__c)) continue;
            CommunicatorThread__c t = selectedThreadByOpp.get(r.Oportunidade__c);
            Integer unread = unreadTotalByOpp.containsKey(r.Oportunidade__c) ? unreadTotalByOpp.get(r.Oportunidade__c) : 0;
            String repasseSinteseName = CommunicatorRepassePhaseHelper.getRepasseSinteseName(r);

            CommunicatorDTOs.ThreadListItemDTO dto = new CommunicatorDTOs.ThreadListItemDTO();
            dto.threadId      = (t != null) ? t.Id : null;
            dto.threadName    = (t != null) ? t.Name : null;
            dto.recordId      = r.Id;
            dto.recordName    = (r.Oportunidade__r != null && !String.isBlank(r.Oportunidade__r.Name))
                ? r.Oportunidade__r.Name
                : r.Name;
            if (isCurrentUserSalesforcePlatform()) {
                dto.recordName = r.Name;
            }
            dto.repasseName          = r.Name;
            dto.repasseOpportunityId = r.Oportunidade__c != null ? String.valueOf(r.Oportunidade__c) : null;
            dto.recordType    = 'Repasse__c';
            dto.hasRepasse    = true;
            dto.stageName     = (t != null) ? t.Stage__c : null;
            String repasseCurrentPhase = CommunicatorRepassePhaseHelper.getMacroPhase(repasseSinteseName);
            dto.currentStage  = String.isNotBlank(repasseCurrentPhase)
                ? repasseCurrentPhase
                : repasseSinteseName;
            dto.displayStatus = dto.currentStage;
            dto.displayStatusLabel = 'Fase atual:';
            dto.rawRepasseStatus = repasseSinteseName;
            dto.statusLabel   = (t != null) ? t.SubStatus__c : null;
            dto.lastSenderId  = (t != null && lastSenderByThreadId.containsKey(t.Id))
                ? String.valueOf(lastSenderByThreadId.get(t.Id))
                : null;
            dto.lastMessageAt = (t != null && t.LastMessageAt__c != null)
                ? t.LastMessageAt__c.format('dd/MM/yyyy HH:mm')
                : '';
            dto.unreadCount   = unread;
            dto.isRead        = unread == 0;
            DateTime repasseLastReadAt = lastReadAtByOpp.get(r.Oportunidade__c);
            dto.lastReadAt    = (repasseLastReadAt != null) ? repasseLastReadAt.format('dd/MM/yyyy HH:mm:ss') : '';

            if (filter == 'unread' && unread == 0) continue;
            if (filter == 'read' && unread > 0) continue;
            result.add(dto);
        }

        // Build DTOs for participant-accessible opportunities that are not in the sharing-visible
        // opps list (e.g., users added via @mention without direct record access).
        Set<Id> mainOppIds = new Map<Id, Opportunity>(opps).keySet();
        for (Id pid : participantOppById.keySet()) {
            if (!oppIds.contains(pid)) continue;
            if (mainOppIds.contains(pid)) continue;
            Opportunity po = participantOppById.get(pid);
            CommunicatorThread__c t = selectedThreadByOpp.get(po.Id);
            Integer unread = unreadTotalByOpp.containsKey(po.Id) ? unreadTotalByOpp.get(po.Id) : 0;
            Repasse__c latestRepasse = latestRepasseByOppId.get(po.Id);
            Boolean displayAsRepasse = hasRepasseByOppId.containsKey(po.Id);
            String repasseSinteseName = CommunicatorRepassePhaseHelper.getRepasseSinteseName(latestRepasse);

            CommunicatorDTOs.ThreadListItemDTO dto = new CommunicatorDTOs.ThreadListItemDTO();
            dto.threadId      = (t != null) ? t.Id : null;
            dto.threadName    = (t != null) ? t.Name : null;
            dto.recordId      = po.Id;
            dto.recordName    = po.Name;
            if (isCurrentUserSalesforcePlatform() && displayAsRepasse && latestRepasse != null) {
                dto.recordName = latestRepasse.Name;
            }
            dto.recordType    = 'Opportunity';
            dto.hasRepasse    = displayAsRepasse;
            dto.stageName     = (t != null) ? t.Stage__c : null;
            String repasseCurrentPhase = repasseMacroPhaseByOppId.get(po.Id);
            dto.currentStage  = displayAsRepasse && String.isNotBlank(repasseCurrentPhase)
                ? repasseCurrentPhase
                : (displayAsRepasse ? repasseSinteseName : effectiveCurrentStageByOppId.get(po.Id));
            dto.displayStatus = dto.currentStage;
            dto.displayStatusLabel = 'Fase atual:';
            dto.rawRepasseStatus  = (displayAsRepasse && latestRepasse != null) ? repasseSinteseName : null;
            dto.statusLabel   = (t != null) ? t.SubStatus__c : null;
            dto.lastSenderId  = (t != null && lastSenderByThreadId.containsKey(t.Id))
                ? String.valueOf(lastSenderByThreadId.get(t.Id))
                : null;
            dto.lastMessageAt = (t != null && t.LastMessageAt__c != null)
                ? t.LastMessageAt__c.format('dd/MM/yyyy HH:mm')
                : '';
            dto.unreadCount   = unread;
            dto.isRead        = unread == 0;
            DateTime partLastReadAt = lastReadAtByOpp.get(po.Id);
            dto.lastReadAt    = (partLastReadAt != null) ? partLastReadAt.format('dd/MM/yyyy HH:mm:ss') : '';

            if (filter == 'unread' && unread == 0) continue;
            if (filter == 'read' && unread > 0) continue;
            result.add(dto);
        }

        // Reorder by thread activity: threads is already ORDER BY LastMessageAt__c DESC.
        // Group DTOs by threadId, then emit in thread order; DTOs with no thread go last.
        if (result.size() > 1 && !threads.isEmpty()) {
            Map<String, List<CommunicatorDTOs.ThreadListItemDTO>> byThreadId =
                new Map<String, List<CommunicatorDTOs.ThreadListItemDTO>>();
            List<CommunicatorDTOs.ThreadListItemDTO> withoutThread =
                new List<CommunicatorDTOs.ThreadListItemDTO>();
            for (CommunicatorDTOs.ThreadListItemDTO dto : result) {
                String tid = (dto.threadId != null) ? String.valueOf(dto.threadId) : null;
                if (tid != null) {
                    if (!byThreadId.containsKey(tid)) {
                        byThreadId.put(tid, new List<CommunicatorDTOs.ThreadListItemDTO>());
                    }
                    byThreadId.get(tid).add(dto);
                } else {
                    withoutThread.add(dto);
                }
            }
            result = new List<CommunicatorDTOs.ThreadListItemDTO>();
            Set<String> added = new Set<String>();
            for (CommunicatorThread__c t : threads) {
                String tid = String.valueOf(t.Id);
                if (!added.contains(tid) && byThreadId.containsKey(tid)) {
                    result.addAll(byThreadId.get(tid));
                    added.add(tid);
                }
            }
            result.addAll(withoutThread);
        }

        // Apply pagination: enforce sz/off on the full sorted result so the compact
        // view's pageSize is respected even in the participant-based no-keyword path.
        if (off > 0 || result.size() > sz) {
            Integer fromIdx = Math.min(off, result.size());
            Integer toIdx   = Math.min(off + sz, result.size());
            List<CommunicatorDTOs.ThreadListItemDTO> paged =
                new List<CommunicatorDTOs.ThreadListItemDTO>();
            for (Integer i = fromIdx; i < toIdx; i++) {
                paged.add(result[i]);
            }
            result = paged;
        }

        return result;
    }

    public static Integer getOpportunityChatCount(String filter, String keyword) {
        String kw = normalizeKeyword(keyword);
        if (isCurrentUserSalesforcePlatform() && !String.isBlank(kw)) {
            return getOpportunityChatList(2000, 0, filter, kw).size();
        }
        String likeKw = buildContainsLikePattern(kw);
        Set<String> cpfSearchValues = buildCpfSearchValues(kw);
        Boolean isSalesforcePlatformUser = isCurrentUserSalesforcePlatform();
        Set<Id> visibleAssessoriaIds = getVisibleAssessoriaIdsForCurrentUser();
        Integer baseCount = getOpportunityBaseCountByLicense(
            isSalesforcePlatformUser,
            kw,
            likeKw,
            cpfSearchValues
        );

        if (!String.isBlank(kw)) {
            Set<Id> candidateOppIds = CommunicatorRepasseService.getCandidateOpportunityIdsByKeyword(
                kw,
                CommunicatorConfigService.getMaxSearchResults(),
                visibleAssessoriaIds
            );
            Set<Id> visibleRepasseOppIds = CommunicatorOpportunityAccessService.getVisibleOpportunityIds(candidateOppIds);
            if (isSalesforcePlatformUser) {
                visibleRepasseOppIds = getEligibleOpportunityIdsForSalesforcePlatform(visibleRepasseOppIds);
            }
            baseCount += CommunicatorRepasseService.countRepassesByOpportunityIds(
                visibleRepasseOppIds,
                kw,
                visibleAssessoriaIds
            );
        }

        // Para filtros read/unread, o count exato exigiria cruzar com notifications.
        // Mantemos o total de oportunidades; a UI usa isso apenas como referência.
        if (filter == 'read' || filter == 'unread') return baseCount;
        return baseCount;
    }

    private static String normalizeKeyword(String keyword) {
        return String.isBlank(keyword) ? '' : keyword.trim();
    }

    private static String escapeLikeValue(String value) {
        if (value == null) return '';
        return value.replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_');
    }

    private static String buildContainsLikePattern(String keyword) {
        if (String.isBlank(keyword)) return '';
        return '%' + escapeLikeValue(keyword) + '%';
    }

    private static String buildPrefixLikePattern(String keyword) {
        if (String.isBlank(keyword)) return '';
        return escapeLikeValue(keyword) + '%';
    }

    private static Set<String> buildCpfSearchValues(String keyword) {
        Set<String> cpfValues = new Set<String>();
        String normalizedKeyword = normalizeKeyword(keyword);
        String cpfDigits = extractDigits(normalizedKeyword);
        if (cpfDigits.length() != 11) return cpfValues;
        cpfValues.add(normalizedKeyword);
        cpfValues.add(formatCpf(cpfDigits));
        return cpfValues;
    }

    private static String extractDigits(String value) {
        return String.isBlank(value) ? '' : value.replaceAll('\\D', '');
    }

    private static String formatCpf(String cpfDigits) {
        if (String.isBlank(cpfDigits) || cpfDigits.length() != 11) return '';
        return cpfDigits.substring(0, 3) + '.'
            + cpfDigits.substring(3, 6) + '.'
            + cpfDigits.substring(6, 9) + '-'
            + cpfDigits.substring(9, 11);
    }

    private static Set<Id> getAdditionalOpportunityIdsByKeyword(
        String keyword,
        Integer limitSize,
        Set<String> cpfSearchValues
    ) {
        Set<Id> opportunityIds = new Set<Id>();
        if (String.isBlank(keyword)) return opportunityIds;

        Integer queryLimit = resolveQueryLimit(limitSize);
        FinancePrefixCriteria financePrefixCriteria = buildFinancePrefixCriteria(keyword);
        opportunityIds.addAll(getOpportunityIdsByArOrCreditoName(financePrefixCriteria, queryLimit));
        opportunityIds.addAll(getOpportunityIdsByAprovacaoName(financePrefixCriteria, queryLimit));
        opportunityIds.addAll(getOpportunityIdsByCpf(cpfSearchValues, queryLimit));
        return opportunityIds;
    }

    private static Integer resolveQueryLimit(Integer limitSize) {
        return (limitSize != null && limitSize > 0) ? limitSize : 20;
    }

    private static FinancePrefixCriteria buildFinancePrefixCriteria(String keyword) {
        FinancePrefixCriteria criteria = new FinancePrefixCriteria();
        String normalizedKeyword = normalizeKeyword(keyword);
        if (String.isBlank(normalizedKeyword)) return criteria;

        criteria.mainPattern = buildPrefixLikePattern(normalizedKeyword);
        String keywordDigits = extractDigits(normalizedKeyword);
        if (keywordDigits.isNumeric()) {
            criteria.arPattern = buildPrefixLikePattern('AR-' + keywordDigits);
            criteria.abPattern = buildPrefixLikePattern('AB-' + keywordDigits);
        }
        return criteria;
    }

    private static Set<Id> getOpportunityIdsByArOrCreditoName(
        FinancePrefixCriteria financePrefixCriteria,
        Integer queryLimit
    ) {
        Set<Id> opportunityIds = new Set<Id>();
        if (financePrefixCriteria == null || String.isBlank(financePrefixCriteria.mainPattern)) {
            return opportunityIds;
        }
        if (financePrefixCriteria.hasNumericPattern()) {
            for (Opportunity opportunityRecord : [
                SELECT Id
                FROM Opportunity
                WHERE ApuracaoRenda__r.Name LIKE :financePrefixCriteria.mainPattern
                OR AnaliseCredito__r.Name LIKE :financePrefixCriteria.mainPattern
                OR ApuracaoRenda__r.Name LIKE :financePrefixCriteria.arPattern
                OR AnaliseCredito__r.Name LIKE :financePrefixCriteria.abPattern
                ORDER BY LastModifiedDate DESC
                LIMIT :queryLimit
            ]) {
                opportunityIds.add(opportunityRecord.Id);
            }
            return opportunityIds;
        }
        for (Opportunity opportunityRecord : [
            SELECT Id
            FROM Opportunity
            WHERE ApuracaoRenda__r.Name LIKE :financePrefixCriteria.mainPattern
            OR AnaliseCredito__r.Name LIKE :financePrefixCriteria.mainPattern
            ORDER BY LastModifiedDate DESC
            LIMIT :queryLimit
        ]) {
            opportunityIds.add(opportunityRecord.Id);
        }
        return opportunityIds;
    }

    private static Set<Id> getOpportunityIdsByAprovacaoName(
        FinancePrefixCriteria financePrefixCriteria,
        Integer queryLimit
    ) {
        Set<Id> opportunityIds = new Set<Id>();
        if (financePrefixCriteria == null || String.isBlank(financePrefixCriteria.mainPattern)) {
            return opportunityIds;
        }
        if (financePrefixCriteria.hasNumericPattern()) {
            for (Opportunity opportunityRecord : [
                SELECT Id
                FROM Opportunity
                WHERE AnaliseCredito__c IN (
                    SELECT AnaliseCredito__c
                    FROM AprovacaoBancaria__c
                    WHERE AnaliseCredito__c != null
                    AND (
                        Name LIKE :financePrefixCriteria.mainPattern
                        OR Name LIKE :financePrefixCriteria.arPattern
                        OR Name LIKE :financePrefixCriteria.abPattern
                    )
                )
                ORDER BY LastModifiedDate DESC
                LIMIT :queryLimit
            ]) {
                opportunityIds.add(opportunityRecord.Id);
            }
            return opportunityIds;
        }
        for (Opportunity opportunityRecord : [
            SELECT Id
            FROM Opportunity
            WHERE AnaliseCredito__c IN (
                SELECT AnaliseCredito__c
                FROM AprovacaoBancaria__c
                WHERE AnaliseCredito__c != null
                AND Name LIKE :financePrefixCriteria.mainPattern
            )
            ORDER BY LastModifiedDate DESC
            LIMIT :queryLimit
        ]) {
            opportunityIds.add(opportunityRecord.Id);
        }
        return opportunityIds;
    }

    private class FinancePrefixCriteria {
        String mainPattern;
        String arPattern;
        String abPattern;

        Boolean hasNumericPattern() {
            return String.isNotBlank(arPattern) && String.isNotBlank(abPattern);
        }
    }

    private static Set<Id> getOpportunityIdsByCpf(Set<String> cpfSearchValues, Integer queryLimit) {
        Set<Id> opportunityIds = new Set<Id>();
        if (cpfSearchValues == null || cpfSearchValues.isEmpty()) return opportunityIds;
        // Person Accounts may not be enabled in every org (for example, POC orgs).
        // Keep the CPF search available where the field exists and degrade gracefully elsewhere.
        if (!hasPersonAccountCpfField()) return opportunityIds;
        String soql = 'SELECT Id FROM Opportunity WHERE Account.CPF__pc IN :cpfSearchValues ORDER BY LastModifiedDate DESC LIMIT :queryLimit';
        for (SObject opportunityRecord : Database.query(soql)) {
            opportunityIds.add(opportunityRecord.Id);
        }
        return opportunityIds;
    }

    private static Boolean hasPersonAccountCpfField() {
        for (String fieldName : Account.SObjectType.getDescribe().fields.getMap().keySet()) {
            if (fieldName.equalsIgnoreCase('CPF__pc')) return true;
        }
        return false;
    }

    private static Set<Id> getMatchedOpportunityIdsByKeyword(
        Set<Id> opportunityIds,
        String keyword,
        Set<Id> repasseCandidateOppIds,
        Set<String> cpfSearchValues
    ) {
        Set<Id> matchedOpportunityIds = new Set<Id>();
        if (opportunityIds == null || opportunityIds.isEmpty()) return matchedOpportunityIds;
        String normalizedKeyword = normalizeKeyword(keyword);
        if (String.isBlank(normalizedKeyword)) return new Set<Id>(opportunityIds);

        Map<Id, Set<Id>> opportunityIdsByAnaliseCreditoId = new Map<Id, Set<Id>>();
        collectDirectKeywordMatches(
            opportunityIds,
            normalizedKeyword,
            cpfSearchValues,
            matchedOpportunityIds,
            opportunityIdsByAnaliseCreditoId
        );
        matchedOpportunityIds.addAll(getAprovacaoMatchedOpportunityIds(
            normalizedKeyword,
            opportunityIdsByAnaliseCreditoId
        ));
        addRepasseKeywordMatches(matchedOpportunityIds, opportunityIds, repasseCandidateOppIds);
        return matchedOpportunityIds;
    }

    private static void collectDirectKeywordMatches(
        Set<Id> opportunityIds,
        String keyword,
        Set<String> cpfSearchValues,
        Set<Id> matchedOpportunityIds,
        Map<Id, Set<Id>> opportunityIdsByAnaliseCreditoId
    ) {
        for (Opportunity opportunityRecord : new OpportunityKeywordBypassReader().getOpportunitiesByIds(opportunityIds)) {
            if (matchesKeywordForOpportunity(opportunityRecord, keyword, cpfSearchValues)) {
                matchedOpportunityIds.add(opportunityRecord.Id);
            }
            addOpportunityIdByAnaliseCredito(opportunityRecord, opportunityIdsByAnaliseCreditoId);
        }
    }

    private static void addOpportunityIdByAnaliseCredito(
        Opportunity opportunityRecord,
        Map<Id, Set<Id>> opportunityIdsByAnaliseCreditoId
    ) {
        if (opportunityRecord == null || opportunityRecord.AnaliseCredito__c == null) return;
        if (!opportunityIdsByAnaliseCreditoId.containsKey(opportunityRecord.AnaliseCredito__c)) {
            opportunityIdsByAnaliseCreditoId.put(opportunityRecord.AnaliseCredito__c, new Set<Id>());
        }
        opportunityIdsByAnaliseCreditoId.get(opportunityRecord.AnaliseCredito__c).add(opportunityRecord.Id);
    }

    private static Set<Id> getAprovacaoMatchedOpportunityIds(
        String keyword,
        Map<Id, Set<Id>> opportunityIdsByAnaliseCreditoId
    ) {
        Set<Id> matchedOpportunityIds = new Set<Id>();
        if (opportunityIdsByAnaliseCreditoId == null || opportunityIdsByAnaliseCreditoId.isEmpty()) {
            return matchedOpportunityIds;
        }
        String containsLikeKeyword = buildContainsLikePattern(keyword);
        for (AprovacaoBancaria__c aprovacaoBancaria : [
            SELECT AnaliseCredito__c
            FROM AprovacaoBancaria__c
            WHERE AnaliseCredito__c IN :opportunityIdsByAnaliseCreditoId.keySet()
            AND Name LIKE :containsLikeKeyword
        ]) {
            matchedOpportunityIds.addAll(opportunityIdsByAnaliseCreditoId.get(aprovacaoBancaria.AnaliseCredito__c));
        }
        return matchedOpportunityIds;
    }

    private static void addRepasseKeywordMatches(
        Set<Id> matchedOpportunityIds,
        Set<Id> opportunityIds,
        Set<Id> repasseCandidateOppIds
    ) {
        if (repasseCandidateOppIds == null || repasseCandidateOppIds.isEmpty()) return;
        for (Id repasseOpportunityId : repasseCandidateOppIds) {
            if (opportunityIds.contains(repasseOpportunityId)) {
                matchedOpportunityIds.add(repasseOpportunityId);
            }
        }
    }

    private static Boolean matchesKeywordForOpportunity(
        Opportunity opportunityRecord,
        String keyword,
        Set<String> cpfSearchValues
    ) {
        if (opportunityRecord == null || String.isBlank(keyword)) return false;
        if (containsIgnoreCase(opportunityRecord.Name, keyword)) return true;
        if (containsIgnoreCase(opportunityRecord.StageName, keyword)) return true;
        if (containsIgnoreCase(opportunityRecord.ApuracaoRenda__r != null ? opportunityRecord.ApuracaoRenda__r.Name : null, keyword)) return true;
        if (containsIgnoreCase(opportunityRecord.AnaliseCredito__r != null ? opportunityRecord.AnaliseCredito__r.Name : null, keyword)) return true;

        String opportunityCpf = null;
        if (hasPersonAccountCpfField() && opportunityRecord.Account != null) {
            opportunityCpf = normalizeKeyword((String) opportunityRecord.Account.get('CPF__pc'));
        }
        if (cpfSearchValues == null || cpfSearchValues.isEmpty()) return false;
        if (cpfSearchValues.contains(opportunityCpf)) return true;

        String keywordDigits = extractDigits(keyword);
        return keywordDigits.length() == 11 && extractDigits(opportunityCpf) == keywordDigits;
    }

    private static Boolean containsIgnoreCase(String sourceValue, String keyword) {
        if (String.isBlank(sourceValue) || String.isBlank(keyword)) return false;
        return sourceValue.toLowerCase().contains(keyword.toLowerCase());
    }

    private static List<Opportunity> filterOpportunitiesByIds(
        List<Opportunity> opportunities,
        Set<Id> allowedOpportunityIds
    ) {
        List<Opportunity> filteredOpportunities = new List<Opportunity>();
        if (opportunities == null || opportunities.isEmpty()) return filteredOpportunities;
        if (allowedOpportunityIds == null || allowedOpportunityIds.isEmpty()) return filteredOpportunities;
        for (Opportunity opportunityRecord : opportunities) {
            if (opportunityRecord == null || opportunityRecord.Id == null) continue;
            if (allowedOpportunityIds.contains(opportunityRecord.Id)) {
                filteredOpportunities.add(opportunityRecord);
            }
        }
        return filteredOpportunities;
    }

    private static void ensureOpportunitiesLoaded(
        List<Opportunity> opportunities,
        Set<Id> opportunityIds,
        Map<Id, String> currentStageByOppId
    ) {
        if (opportunities == null || opportunityIds == null || opportunityIds.isEmpty()) return;
        Set<Id> loadedOpportunityIds = new Map<Id, Opportunity>(opportunities).keySet();
        Set<Id> missingOpportunityIds = new Set<Id>(opportunityIds);
        missingOpportunityIds.removeAll(loadedOpportunityIds);
        if (missingOpportunityIds.isEmpty()) return;
        for (Opportunity opportunityRecord : CommunicatorOpportunityDataService.getOpportunitiesByIds(missingOpportunityIds)) {
            opportunities.add(opportunityRecord);
            if (!currentStageByOppId.containsKey(opportunityRecord.Id)) {
                currentStageByOppId.put(opportunityRecord.Id, opportunityRecord.StageName);
            }
        }
    }

    public static List<CommunicatorDTOs.ThreadPresenceOverrideDTO> getThreadPresenceOverrides(List<Id> threadIds) {
        Set<Id> normalizedThreadIds = normalizeThreadIds(threadIds);
        if (normalizedThreadIds.isEmpty()) return new List<CommunicatorDTOs.ThreadPresenceOverrideDTO>();

        Map<Id, Id> oppIdByThreadId = resolveOpportunityIdsByThreadId(normalizedThreadIds);
        if (oppIdByThreadId.isEmpty()) return new List<CommunicatorDTOs.ThreadPresenceOverrideDTO>();

        Map<Id, AnaliseFinanceira__c> apuracaoByOppId = getApuracaoRendaByOpportunityId(new Set<Id>(oppIdByThreadId.values()));
        if (apuracaoByOppId.isEmpty()) return new List<CommunicatorDTOs.ThreadPresenceOverrideDTO>();

        Map<Id, Boolean> isPlatformByUserId = getSalesforcePlatformByUserId(collectAnalistaIds(apuracaoByOppId));
        return buildThreadPresenceOverrides(oppIdByThreadId, apuracaoByOppId, isPlatformByUserId);
    }

    private static Set<Id> normalizeThreadIds(List<Id> threadIds) {
        Set<Id> normalized = new Set<Id>();
        if (threadIds == null) return normalized;
        for (Id threadId : threadIds) {
            if (threadId != null) normalized.add(threadId);
        }
        return normalized;
    }

    private static Map<Id, Id> resolveOpportunityIdsByThreadId(Set<Id> threadIds) {
        Map<Id, Id> oppIdByThreadId = new Map<Id, Id>();
        Map<Id, Id> threadIdByRepasseId = new Map<Id, Id>();
        Map<Id, Id> threadIdByAnaliseId = new Map<Id, Id>();

        for (CommunicatorThread__c threadRecord : [
            SELECT Id, RecordId__c, RecordType__c
            FROM CommunicatorThread__c
            WHERE Id IN :threadIds
        ]) {
            classifyThreadRecord(threadRecord, oppIdByThreadId, threadIdByRepasseId, threadIdByAnaliseId);
        }
        addThreadOpportunityMappings(oppIdByThreadId, threadIdByRepasseId, getOpportunityIdsByRepasseId(threadIdByRepasseId.keySet()));
        addThreadOpportunityMappings(oppIdByThreadId, threadIdByAnaliseId, getOpportunityIdsByAnaliseId(threadIdByAnaliseId.keySet()));
        return oppIdByThreadId;
    }

    private static void classifyThreadRecord(
        CommunicatorThread__c threadRecord,
        Map<Id, Id> oppIdByThreadId,
        Map<Id, Id> threadIdByRepasseId,
        Map<Id, Id> threadIdByAnaliseId
    ) {
        if (threadRecord == null || String.isBlank(threadRecord.RecordId__c)) return;
        Id recordId = safeCastId(threadRecord.RecordId__c);
        if (recordId == null) return;
        String recordType = String.isBlank(threadRecord.RecordType__c)
            ? recordId.getSObjectType().getDescribe().getName()
            : threadRecord.RecordType__c;

        if (recordType == 'Opportunity') oppIdByThreadId.put(threadRecord.Id, recordId);
        else if (recordType == 'Repasse__c') threadIdByRepasseId.put(recordId, threadRecord.Id);
        else if (recordType == 'AnaliseFinanceira__c') threadIdByAnaliseId.put(recordId, threadRecord.Id);
    }

    private static void addThreadOpportunityMappings(
        Map<Id, Id> oppIdByThreadId,
        Map<Id, Id> threadIdByRecordId,
        Map<Id, Id> oppIdByRecordId
    ) {
        if (oppIdByThreadId == null || threadIdByRecordId == null || oppIdByRecordId == null) return;
        for (Id recordId : threadIdByRecordId.keySet()) {
            if (!oppIdByRecordId.containsKey(recordId)) continue;
            oppIdByThreadId.put(threadIdByRecordId.get(recordId), oppIdByRecordId.get(recordId));
        }
    }

    private static Map<Id, Id> getOpportunityIdsByRepasseId(Set<Id> repasseIds) {
        Map<Id, Id> oppByRepasseId = new Map<Id, Id>();
        if (repasseIds == null || repasseIds.isEmpty()) return oppByRepasseId;
        for (Repasse__c repasse : [
            SELECT Id, Oportunidade__c
            FROM Repasse__c
            WHERE Id IN :repasseIds
        ]) {
            if (repasse.Oportunidade__c != null) oppByRepasseId.put(repasse.Id, repasse.Oportunidade__c);
        }
        return oppByRepasseId;
    }

    private static Map<Id, Id> getOpportunityIdsByAnaliseId(Set<Id> analiseIds) {
        Map<Id, Id> oppByAnaliseId = new Map<Id, Id>();
        if (analiseIds == null || analiseIds.isEmpty()) return oppByAnaliseId;
        for (AnaliseFinanceira__c analise : [
            SELECT Id, Oportunidade__c
            FROM AnaliseFinanceira__c
            WHERE Id IN :analiseIds
        ]) {
            if (analise.Oportunidade__c != null) oppByAnaliseId.put(analise.Id, analise.Oportunidade__c);
        }
        return oppByAnaliseId;
    }

    private static Map<Id, AnaliseFinanceira__c> getApuracaoRendaByOpportunityId(Set<Id> opportunityIds) {
        Map<Id, Id> apuracaoByOppId = new Map<Id, Id>();
        if (opportunityIds == null || opportunityIds.isEmpty()) return new Map<Id, AnaliseFinanceira__c>();

        ApuracaoPresenceBypassReader reader = new ApuracaoPresenceBypassReader();
        for (Opportunity opportunityRecord : reader.getOpportunitiesByIds(opportunityIds)) {
            if (opportunityRecord.ApuracaoRenda__c == null) continue;
            apuracaoByOppId.put(opportunityRecord.Id, opportunityRecord.ApuracaoRenda__c);
        }
        if (apuracaoByOppId.isEmpty()) return new Map<Id, AnaliseFinanceira__c>();

        Map<Id, AnaliseFinanceira__c> apuracaoById =
            new Map<Id, AnaliseFinanceira__c>(
                reader.getApuracoesByIds(new Set<Id>(apuracaoByOppId.values()))
            );

        Map<Id, AnaliseFinanceira__c> apuracaoByOpportunityId = new Map<Id, AnaliseFinanceira__c>();
        for (Id opportunityId : apuracaoByOppId.keySet()) {
            Id apuracaoId = apuracaoByOppId.get(opportunityId);
            if (apuracaoById.containsKey(apuracaoId)) {
                apuracaoByOpportunityId.put(opportunityId, apuracaoById.get(apuracaoId));
            }
        }
        return apuracaoByOpportunityId;
    }

    private static Set<Id> collectAnalistaIds(Map<Id, AnaliseFinanceira__c> apuracaoByOppId) {
        Set<Id> analystIds = new Set<Id>();
        if (apuracaoByOppId == null) return analystIds;
        for (AnaliseFinanceira__c apuracao : apuracaoByOppId.values()) {
            if (apuracao != null && apuracao.AnalistaResponsavel__c != null) {
                analystIds.add(apuracao.AnalistaResponsavel__c);
            }
        }
        return analystIds;
    }

    private static Map<Id, Boolean> getSalesforcePlatformByUserId(Set<Id> userIds) {
        Map<Id, Boolean> flagsByUserId = new Map<Id, Boolean>();
        if (userIds == null || userIds.isEmpty()) return flagsByUserId;

        for (User userRecord : [
            SELECT Id, Profile.UserLicense.Name
            FROM User
            WHERE Id IN :userIds
        ]) {
            flagsByUserId.put(
                userRecord.Id,
                userRecord.Profile != null
                    && userRecord.Profile.UserLicense != null
                    && userRecord.Profile.UserLicense.Name == 'Salesforce Platform'
            );
        }
        return flagsByUserId;
    }

    private static List<CommunicatorDTOs.ThreadPresenceOverrideDTO> buildThreadPresenceOverrides(
        Map<Id, Id> oppIdByThreadId,
        Map<Id, AnaliseFinanceira__c> apuracaoByOppId,
        Map<Id, Boolean> isPlatformByUserId
    ) {
        List<CommunicatorDTOs.ThreadPresenceOverrideDTO> overrides = new List<CommunicatorDTOs.ThreadPresenceOverrideDTO>();
        for (Id threadId : oppIdByThreadId.keySet()) {
            Id opportunityId = oppIdByThreadId.get(threadId);
            AnaliseFinanceira__c apuracao = apuracaoByOppId.get(opportunityId);
            if (apuracao == null || apuracao.AnalistaResponsavel__c == null) continue;
            if (!isSalesforcePlatformPresenceUser(apuracao.AnalistaResponsavel__c, isPlatformByUserId)) continue;

            CommunicatorDTOs.ThreadPresenceOverrideDTO dto = new CommunicatorDTOs.ThreadPresenceOverrideDTO();
            dto.threadId = String.valueOf(threadId);
            dto.userId = String.valueOf(apuracao.AnalistaResponsavel__c);
            dto.status = isAnaliseEmTrabalho(apuracao) ? 'online' : 'offline';
            overrides.add(dto);
        }
        return overrides;
    }

    private static Boolean isSalesforcePlatformPresenceUser(Id userId, Map<Id, Boolean> isPlatformByUserId) {
        if (userId == null) return false;
        if (Test.isRunningTest() && forceSalesforcePlatformPresenceUsersForTest != null) {
            return forceSalesforcePlatformPresenceUsersForTest.contains(userId);
        }
        return isPlatformByUserId != null && isPlatformByUserId.get(userId) == true;
    }

    private static Boolean isAnaliseEmTrabalho(AnaliseFinanceira__c apuracao) {
        if (apuracao == null) return false;
        String status = normalizeCommunicatorStage(apuracao.Status__c);
        String approvalStatus = normalizeCommunicatorStage(apuracao.StatusAprovacao__c);
        return status == 'em analise' || approvalStatus == 'em analise';
    }

    private static Id safeCastId(String value) {
        try {
            return (Id) value;
        } catch (Exception ex) {
            return null;
        }
    }

    private static Integer getOpportunityBaseCountByLicense(Boolean isSalesforcePlatformUser, String kw, String likeKw) {
        return getOpportunityBaseCountByLicense(isSalesforcePlatformUser, kw, likeKw, new Set<String>());
    }

    private static Integer getOpportunityBaseCountByLicense(
        Boolean isSalesforcePlatformUser,
        String kw,
        String likeKw,
        Set<String> cpfSearchValues
    ) {
        return isSalesforcePlatformUser
            ? getSalesforcePlatformOpportunityCount(kw, likeKw, cpfSearchValues)
            : getDefaultOpportunityCount(kw, likeKw, cpfSearchValues);
    }

    private static Integer getDefaultOpportunityCount(String kw, String likeKw, Set<String> cpfSearchValues) {
        if (String.isBlank(kw)) return [SELECT COUNT() FROM Opportunity];

        String cpfCondition = hasPersonAccountCpfField() ? ' OR Account.CPF__pc IN :cpfSearchValues' : '';
        String directQuery = 'SELECT COUNT() FROM Opportunity WHERE Name LIKE :likeKw OR StageName LIKE :likeKw'
            + ' OR ApuracaoRenda__r.Name LIKE :likeKw OR AnaliseCredito__r.Name LIKE :likeKw'
            + cpfCondition;
        Integer directCount = Database.countQuery(directQuery);
        Set<Id> analiseCreditoIdsByAprovacao = getAnaliseCreditoIdsByAprovacaoKeyword(likeKw);
        if (analiseCreditoIdsByAprovacao.isEmpty()) return directCount;

        String aprovacaoQuery = 'SELECT COUNT() FROM Opportunity WHERE AnaliseCredito__c IN :analiseCreditoIdsByAprovacao'
            + ' AND (NOT (Name LIKE :likeKw OR StageName LIKE :likeKw OR ApuracaoRenda__r.Name LIKE :likeKw'
            + ' OR AnaliseCredito__r.Name LIKE :likeKw' + cpfCondition + '))';
        Integer aprovacaoOnlyCount = Database.countQuery(aprovacaoQuery);
        return directCount + aprovacaoOnlyCount;
    }

    private static Integer getSalesforcePlatformOpportunityCount(
        String kw,
        String likeKw,
        Set<String> cpfSearchValues
    ) {
        Set<Id> visibleAssessoriaIds = getVisibleAssessoriaIdsForCurrentUser();
        if (visibleAssessoriaIds != null && !visibleAssessoriaIds.isEmpty()) {
            if (String.isBlank(kw)) {
                return [
                    SELECT COUNT()
                    FROM Opportunity
                    WHERE AssessoriaCredito__c IN :visibleAssessoriaIds
                ];
            }

            String cpfCondition = hasPersonAccountCpfField() ? ' OR Account.CPF__pc IN :cpfSearchValues' : '';
            String soql = 'SELECT COUNT() FROM Opportunity WHERE AssessoriaCredito__c IN :visibleAssessoriaIds'
                + ' AND (Name LIKE :likeKw OR StageName LIKE :likeKw OR ApuracaoRenda__r.Name LIKE :likeKw'
                + ' OR AnaliseCredito__r.Name LIKE :likeKw' + cpfCondition + ')';
            return Database.countQuery(soql);
        }

        Set<Id> userQueueIds = getCurrentUserQueueIds();
        if (userQueueIds.isEmpty()) return 0;

        Integer countWithApuracao;
        if (String.isBlank(kw)) {
            countWithApuracao = [SELECT COUNT() FROM Opportunity
               WHERE ApuracaoRenda__c != null AND ApuracaoRenda__r.OwnerId IN :userQueueIds];
        } else {
            String cpfCondition = hasPersonAccountCpfField() ? ' OR Account.CPF__pc IN :cpfSearchValues' : '';
            String soql = 'SELECT COUNT() FROM Opportunity WHERE (Name LIKE :likeKw OR StageName LIKE :likeKw'
                + ' OR ApuracaoRenda__r.Name LIKE :likeKw OR AnaliseCredito__r.Name LIKE :likeKw'
                + cpfCondition + ') AND ApuracaoRenda__c != null AND ApuracaoRenda__r.OwnerId IN :userQueueIds';
            countWithApuracao = Database.countQuery(soql);
        }

        Set<Id> aprovacaoAnaliseIds = getAnaliseCreditoIdsFromAnyAprovacao();
        if (aprovacaoAnaliseIds.isEmpty()) return countWithApuracao;
        Set<Id> keywordAprovacaoAnaliseIds = String.isBlank(kw)
            ? aprovacaoAnaliseIds
            : getAnaliseCreditoIdsByAprovacaoKeyword(likeKw);

        Integer countWithAprovacaoOnly = String.isBlank(kw)
            ? [
                SELECT COUNT()
                FROM Opportunity
                WHERE ApuracaoRenda__c = null
                AND AnaliseCredito__c IN :aprovacaoAnaliseIds
            ]
            : getSalesforcePlatformAprovacaoOnlyCount(
                likeKw,
                cpfSearchValues,
                aprovacaoAnaliseIds,
                keywordAprovacaoAnaliseIds
            );
        return countWithApuracao + countWithAprovacaoOnly;
    }

    private static Integer getSalesforcePlatformAprovacaoOnlyCount(
        String likeKw,
        Set<String> cpfSearchValues,
        Set<Id> aprovacaoAnaliseIds,
        Set<Id> keywordAprovacaoAnaliseIds
    ) {
        if (aprovacaoAnaliseIds == null || aprovacaoAnaliseIds.isEmpty()) return 0;
        if (keywordAprovacaoAnaliseIds == null) keywordAprovacaoAnaliseIds = new Set<Id>();
        String cpfCondition = hasPersonAccountCpfField() ? ' OR Account.CPF__pc IN :cpfSearchValues' : '';
        String soql = 'SELECT COUNT() FROM Opportunity WHERE ApuracaoRenda__c = null'
            + ' AND AnaliseCredito__c IN :aprovacaoAnaliseIds'
            + ' AND (Name LIKE :likeKw OR StageName LIKE :likeKw OR AnaliseCredito__r.Name LIKE :likeKw'
            + cpfCondition + ' OR AnaliseCredito__c IN :keywordAprovacaoAnaliseIds)';
        return Database.countQuery(soql);
    }

    private static Set<Id> getAnaliseCreditoIdsByAprovacaoKeyword(String likeKw) {
        Set<Id> analiseCreditoIds = new Set<Id>();
        if (String.isBlank(likeKw)) return analiseCreditoIds;
        for (AprovacaoBancaria__c aprovacaoBancaria : [
            SELECT AnaliseCredito__c
            FROM AprovacaoBancaria__c
            WHERE AnaliseCredito__c != null
            AND Name LIKE :likeKw
        ]) {
            analiseCreditoIds.add(aprovacaoBancaria.AnaliseCredito__c);
        }
        return analiseCreditoIds;
    }

    private static Set<Id> getAnaliseCreditoIdsFromAnyAprovacao() {
        Set<Id> analiseCreditoIds = new Set<Id>();
        for (AprovacaoBancaria__c aprovacaoBancaria : [
            SELECT AnaliseCredito__c
            FROM AprovacaoBancaria__c
            WHERE AnaliseCredito__c != null
            LIMIT 2000
        ]) {
            analiseCreditoIds.add(aprovacaoBancaria.AnaliseCredito__c);
        }
        return analiseCreditoIds;
    }

    private static Set<Id> getEligibleOpportunityIdsForSalesforcePlatform(Set<Id> opportunityIds) {
        if (opportunityIds == null || opportunityIds.isEmpty()) return new Set<Id>();
        Set<Id> visibleAssessoriaIds = getVisibleAssessoriaIdsForCurrentUser();
        if (visibleAssessoriaIds != null && !visibleAssessoriaIds.isEmpty()) {
            return CommunicatorOpportunityAccessService.getVisibleOpportunityIds(opportunityIds);
        }
        Set<Id> userQueueIds = getCurrentUserQueueIds();
        Set<Id> eligibleOpportunityIds = getOpportunityIdsWithApuracaoRenda(opportunityIds, userQueueIds);
        eligibleOpportunityIds.addAll(
            getOpportunityIdsWithAprovacaoBancaria(opportunityIds, eligibleOpportunityIds)
        );
        return eligibleOpportunityIds;
    }

    private static Set<Id> getOpportunityIdsWithApuracaoRenda(Set<Id> opportunityIds, Set<Id> userQueueIds) {
        Set<Id> opportunityIdsWithApuracaoRenda = new Set<Id>();
        if (userQueueIds == null || userQueueIds.isEmpty()) return opportunityIdsWithApuracaoRenda;
        for (Opportunity opportunityRecord : [
            SELECT Id
            FROM Opportunity
            WHERE Id                       IN :opportunityIds
            AND   ApuracaoRenda__c         != null
            AND   ApuracaoRenda__r.OwnerId IN :userQueueIds
        ]) {
            opportunityIdsWithApuracaoRenda.add(opportunityRecord.Id);
        }
        return opportunityIdsWithApuracaoRenda;
    }

    private static Set<Id> getOpportunityIdsWithAprovacaoBancaria(Set<Id> opportunityIds, Set<Id> alreadyEligibleIds) {
        Map<Id, Set<Id>> opportunityIdsByAnaliseCreditoId = new Map<Id, Set<Id>>();
        for (Opportunity opportunityRecord : [
            SELECT Id, AnaliseCredito__c
            FROM Opportunity
            WHERE Id IN :opportunityIds
            AND Id NOT IN :alreadyEligibleIds
            AND AnaliseCredito__c != null
        ]) {
            if (!opportunityIdsByAnaliseCreditoId.containsKey(opportunityRecord.AnaliseCredito__c)) {
                opportunityIdsByAnaliseCreditoId.put(opportunityRecord.AnaliseCredito__c, new Set<Id>());
            }
            opportunityIdsByAnaliseCreditoId.get(opportunityRecord.AnaliseCredito__c).add(opportunityRecord.Id);
        }
        Set<Id> opportunityIdsWithAprovacaoBancaria = new Set<Id>();
        if (opportunityIdsByAnaliseCreditoId.isEmpty()) return opportunityIdsWithAprovacaoBancaria;

        for (AprovacaoBancaria__c aprovacaoBancaria : [
            SELECT AnaliseCredito__c
            FROM AprovacaoBancaria__c
            WHERE AnaliseCredito__c IN :opportunityIdsByAnaliseCreditoId.keySet()
        ]) {
            opportunityIdsWithAprovacaoBancaria.addAll(
                opportunityIdsByAnaliseCreditoId.get(aprovacaoBancaria.AnaliseCredito__c)
            );
        }
        return opportunityIdsWithAprovacaoBancaria;
    }

    private static Boolean isCurrentUserSalesforcePlatform() {
        if (Test.isRunningTest() && useSalesforcePlatformOverrideForTest == true) {
            return forceSalesforcePlatformUserForTest == true;
        }
        if (Test.isRunningTest()) {
            return true;
        }
        if (isSalesforcePlatformUserCacheInitialized) {
            return isSalesforcePlatformUserCache == true;
        }
        User currentUser = [
            SELECT Profile.UserLicense.Name
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];
        isSalesforcePlatformUserCache =
            currentUser.Profile != null
            && currentUser.Profile.UserLicense != null
            && currentUser.Profile.UserLicense.Name == 'Salesforce Platform';
        isSalesforcePlatformUserCacheInitialized = true;
        return isSalesforcePlatformUserCache == true;
    }

    private static Boolean isCurrentExperienceContext() {
        return Network.getNetworkId() != null;
    }

    @TestVisible
    private static Set<Id> testQueueIdsOverride;

    private static Set<Id> getCurrentUserQueueIds() {
        if (Test.isRunningTest() && testQueueIdsOverride != null) {
            return testQueueIdsOverride;
        }
        if (currentUserQueueIdsCacheInitialized) {
            return new Set<Id>(currentUserQueueIdsCache);
        }
        Id userId = UserInfo.getUserId();
        User currentUser = [
            SELECT UserRoleId
            FROM User
            WHERE Id = :userId
            LIMIT 1
        ];

        Set<Id> seedGroupIds = new Set<Id>();
        if (currentUser.UserRoleId != null) {
            for (Group roleGroup : [
                SELECT Id
                FROM Group
                WHERE Type = 'Role'
                AND RelatedId = :currentUser.UserRoleId
            ]) {
                seedGroupIds.add(roleGroup.Id);
            }
        }

        Set<Id> queueIds = new Set<Id>();
        Set<Id> visitedGroupIds = new Set<Id>();
        Set<Id> frontierIds = new Set<Id>();
        frontierIds.add(userId);
        frontierIds.addAll(seedGroupIds);

        Integer safetyDepth = 0;
        while (!frontierIds.isEmpty() && safetyDepth < 10) {
            safetyDepth++;
            Set<Id> nextFrontier = new Set<Id>();
            for (GroupMember gm : [
                SELECT GroupId, UserOrGroupId, Group.Type
                FROM GroupMember
                WHERE UserOrGroupId IN :frontierIds
            ]) {
                if (gm.GroupId == null || visitedGroupIds.contains(gm.GroupId)) continue;
                visitedGroupIds.add(gm.GroupId);
                if (gm.Group != null && gm.Group.Type == 'Queue') {
                    queueIds.add(gm.GroupId);
                } else {
                    nextFrontier.add(gm.GroupId);
                }
            }
            frontierIds = nextFrontier;
        }
        currentUserQueueIdsCache = new Set<Id>(queueIds);
        currentUserQueueIdsCacheInitialized = true;
        return new Set<Id>(currentUserQueueIdsCache);
    }

    // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    // Private helpers
    // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

    public static Set<Id> getVisibleAssessoriaIdsForCurrentUser() {
        if (!isCurrentUserSalesforcePlatform()) {
            return null;
        }
        if (currentUserAssessoriaIdsCacheInitialized) {
            if (currentUserAssessoriaIdsCache == null) {
                return null;
            }
            return new Set<Id>(currentUserAssessoriaIdsCache);
        }

        Set<Id> userQueueIds = getCurrentUserQueueIds();
        Set<Id> assessoriaIds = CommunicatorRepasseService.getAssessoriaIdsByQueueIds(userQueueIds);
        if (assessoriaIds == null || assessoriaIds.isEmpty()) {
            if (Test.isRunningTest() && testQueueIdsOverride != null) {
                currentUserAssessoriaIdsCache = new Set<Id>();
                currentUserAssessoriaIdsCacheInitialized = true;
                return new Set<Id>();
            }
            currentUserAssessoriaIdsCache = null;
            currentUserAssessoriaIdsCacheInitialized = true;
            return null;
        }

        currentUserAssessoriaIdsCache = new Set<Id>(assessoriaIds);
        currentUserAssessoriaIdsCacheInitialized = true;
        return new Set<Id>(currentUserAssessoriaIdsCache);
    }

    public static Map<Id, Repasse__c> getVisibleLatestRepassesByOpportunityIds(Set<Id> opportunityIds) {
        Set<Id> visibleAssessoriaIds = getVisibleAssessoriaIdsForCurrentUser();
        return CommunicatorRepasseService.getLatestRepassesByOpportunityIds(
            opportunityIds,
            (visibleAssessoriaIds != null && !visibleAssessoriaIds.isEmpty())
                ? visibleAssessoriaIds
                : null
        );
    }

    public static Boolean isRepasseVisibleForCurrentUser(Repasse__c repasse) {
        if (repasse == null) return false;
        if (!isCurrentUserSalesforcePlatform()) return true;
        Set<Id> assessoriaIds = getVisibleAssessoriaIdsForCurrentUser();
        if (assessoriaIds != null && !assessoriaIds.isEmpty()) {
            if (repasse.ContaAssessoria__c == null) return false;
            return assessoriaIds.contains(repasse.ContaAssessoria__c);
        }
        return true;
    }

    private static CommunicatorThread__c createThread(String recordId, String resolvedType, String stage) {
        CommunicatorThread__c thread = new CommunicatorThread__c(
            RecordId__c   = recordId,
            RecordType__c = resolvedType,
            Stage__c      = stage,
            Status__c     = 'Active'
        );
        insert thread;

        ensureCurrentUserIsParticipant(thread.Id);
        return thread;
    }

    private static void ensureCurrentUserIsParticipant(Id threadId) {
        Id currentUserId = UserInfo.getUserId();

        Integer existing = [
            SELECT COUNT()
            FROM CommunicatorParticipant__c
            WHERE Thread__c = :threadId
            AND   User__c   = :currentUserId
        ];

        if (existing == 0) {
            insert new CommunicatorParticipant__c(
                Thread__c   = threadId,
                User__c     = currentUserId,
                IsActive__c = true
            );
        }
    }

    /**
     * @description Returns full detail for a single thread, including resolved record name.
     * @param threadId Id of the CommunicatorThread__c record.
     * @return ThreadListItemDTO with all fields populated.
     */
    public static CommunicatorDTOs.ThreadListItemDTO getThreadDetail(Id threadId) {
        List<CommunicatorThread__c> rows = [
            SELECT Id, Name, RecordId__c, RecordType__c, Stage__c, SubStatus__c, LastMessageAt__c
            FROM   CommunicatorThread__c
            WHERE  Id = :threadId
            LIMIT  1
        ];
        if (rows.isEmpty()) return new CommunicatorDTOs.ThreadListItemDTO();

        CommunicatorThread__c t = rows[0];
        CommunicatorDTOs.ThreadListItemDTO dto = new CommunicatorDTOs.ThreadListItemDTO();
        dto.threadId    = t.Id;
        dto.threadName  = t.Name;
        dto.recordId    = t.RecordId__c;
        dto.recordType  = t.RecordType__c;
        dto.stageName   = t.Stage__c;
        dto.statusLabel = t.SubStatus__c;
        dto.recordName  = t.Name; // fallback

        if (!String.isBlank(t.RecordId__c)) {
            try {
                Id      recId  = (Id) t.RecordId__c;
                String  obj    = recId.getSObjectType().getDescribe().getName();
                if (obj == 'Repasse__c') {
                    Map<Id, Repasse__c> repassesById = CommunicatorRepasseService.getRepassesByIds(new Set<Id>{ recId });
                    Repasse__c repasse = repassesById.get(recId);
                    if (repasse == null) {
                        dto.recordName = '';
                    } else if (isCurrentUserSalesforcePlatform() && !isRepasseVisibleForCurrentUser(repasse)) {
                        return new CommunicatorDTOs.ThreadListItemDTO();
                    } else {
                        dto.recordName = repasse.Name;
                    }
                } else {
                    List<SObject> recs = Database.query(
                        'SELECT Name FROM ' + obj + ' WHERE Id = :recId LIMIT 1'
                    );
                    if (!recs.isEmpty()) dto.recordName = (String) recs[0].get('Name');

                    if (obj == 'Opportunity' && isCurrentUserSalesforcePlatform()) {
                        String repassePhase = CommunicatorRepassePhaseHelper.getRepasseMacroPhaseByOppId(recId);
                        if (String.isNotBlank(repassePhase)) {
                            Map<Id, Repasse__c> repassesByOppId = getVisibleLatestRepassesByOpportunityIds(
                                new Set<Id>{ recId }
                            );
                            Repasse__c repasse = repassesByOppId.get(recId);
                            if (repasse != null) {
                                dto.recordName = repasse.Name;
                            }
                        }
                    }
                }
            } catch (Exception e) { /* keep fallback */ }
        }
        return dto;
    }

    /**
     * @description Returns all non-archived threads linked to a given record.
     *              Used to populate the stage-tab carousel on the history page.
     * @param recordId RecordId__c value (any SObject Id).
     * @return List of ThreadListItemDTO, ordered by LastMessageAt ASC.
     */
    public static List<CommunicatorDTOs.ThreadListItemDTO> getThreadsForRecord(String recordId) {
        return getThreadsForRecordInternal(recordId, false);
    }

    public static List<CommunicatorDTOs.ThreadListItemDTO> getThreadsForRecordPreview(String recordId) {
        return getThreadsForRecordInternal(recordId, true);
    }

    private static List<CommunicatorDTOs.ThreadListItemDTO> getThreadsForRecordInternal(
        String recordId,
        Boolean includePreviewThreads
    ) {
        if (String.isBlank(recordId)) return new List<CommunicatorDTOs.ThreadListItemDTO>();
        if (isCurrentUserSalesforcePlatform()) {
            try {
                Id sfId = (Id) recordId;
                if (sfId.getSObjectType().getDescribe().getName() == 'Repasse__c') {
                    Map<Id, Repasse__c> repassesById = CommunicatorRepasseService.getRepassesByIds(new Set<Id>{ sfId });
                    Repasse__c repasse = repassesById.get(sfId);
                    if (!isRepasseVisibleForCurrentUser(repasse)) {
                        return new List<CommunicatorDTOs.ThreadListItemDTO>();
                    }
                }
            } catch (Exception e) { /* keep fallback */ }
        }
        recordId = resolveOpportunityIdIfRepasse(recordId);
        Set<Id> visibleThreadIds = includePreviewThreads
            ? new Set<Id>()
            : getThreadIdsVisibleInCurrentUserList();
        if (!includePreviewThreads && visibleThreadIds.isEmpty()) {
            return new List<CommunicatorDTOs.ThreadListItemDTO>();
        }
        Boolean isExperienceContext = isCurrentExperienceContext();

        List<CommunicatorThread__c> threads;
        if (!isExperienceContext) {
            if (includePreviewThreads) {
                threads = [
                    SELECT Id, Name, RecordId__c, RecordType__c, Stage__c, LastMessageAt__c
                    FROM   CommunicatorThread__c
                    WHERE  RecordId__c = :recordId
                    AND    Status__c  != 'Archived'
                    ORDER BY LastMessageAt__c ASC NULLS LAST
                ];
            } else {
                threads = [
                    SELECT Id, Name, RecordId__c, RecordType__c, Stage__c, LastMessageAt__c
                    FROM   CommunicatorThread__c
                    WHERE  Id IN :visibleThreadIds
                    AND    RecordId__c = :recordId
                    AND    Status__c  != 'Archived'
                    ORDER BY LastMessageAt__c ASC NULLS LAST
                ];
            }
        } else if (includePreviewThreads) {
            threads = new CommunityThreadBypassReader().getThreadsByRecordId(recordId);
        } else {
            // Em Experience Cloud, a leitura do objeto de thread precisa do bypass tecnico,
            // mas ainda continua limitada aos mesmos IDs visiveis na listagem do comunicador.
            threads = new CommunityThreadBypassReader().getThreadsByIds(visibleThreadIds, recordId);
        }
        if (threads.isEmpty()) return new List<CommunicatorDTOs.ThreadListItemDTO>();

        // Per-thread unread count for the current user
        Set<Id> fetchedIds = new Set<Id>();
        for (CommunicatorThread__c t : threads) fetchedIds.add(t.Id);

        Id userId = UserInfo.getUserId();
        Map<Id, Integer> unreadByThread = new Map<Id, Integer>();
        for (AggregateResult ar : [
            SELECT Thread__c tid, COUNT(Id) cnt
            FROM   CommunicatorNotification__c
            WHERE  Thread__c    IN :fetchedIds
            AND    Recipient__c = :userId
            AND    IsRead__c    = false
            GROUP  BY Thread__c
        ]) {
            unreadByThread.put((Id) ar.get('tid'), Integer.valueOf(ar.get('cnt')));
        }

        Map<Id, CommunicatorMessage__c> lastMessageByThread = new Map<Id, CommunicatorMessage__c>();
        List<CommunicatorMessage__c> rawMessages = !isExperienceContext
            ? [
                SELECT Thread__c, Body__c, SentAt__c, Sender__r.Name, Sender__r.SmallPhotoUrl, IsSystemMessage__c
                FROM   CommunicatorMessage__c
                WHERE  Thread__c IN :fetchedIds
                ORDER BY SentAt__c DESC, Id DESC
              ]
            : new CommunityThreadBypassReader().getLastMessagesByThreadIds(fetchedIds);
        for (CommunicatorMessage__c msg : rawMessages) {
            if (!lastMessageByThread.containsKey(msg.Thread__c)) {
                lastMessageByThread.put(msg.Thread__c, msg);
            }
        }
        Map<Id, CommunicatorMessage__c> lastEventByThread =
            CommunicatorSystemEventService.getLatestEventByThread(fetchedIds);
        for (Id threadId : lastEventByThread.keySet()) {
            CommunicatorMessage__c evt = lastEventByThread.get(threadId);
            CommunicatorMessage__c current = lastMessageByThread.get(threadId);
            if (current == null || current.SentAt__c == null || evt.SentAt__c > current.SentAt__c) {
                lastMessageByThread.put(threadId, evt);
            }
        }

        List<CommunicatorDTOs.ThreadListItemDTO> result = new List<CommunicatorDTOs.ThreadListItemDTO>();
        for (CommunicatorThread__c t : threads) {
            CommunicatorDTOs.ThreadListItemDTO dto = new CommunicatorDTOs.ThreadListItemDTO();
            dto.threadId    = t.Id;
            dto.threadName  = t.Name;
            dto.recordId    = t.RecordId__c;
            dto.recordType  = t.RecordType__c;
            dto.stageName   = t.Stage__c;
            dto.lastMessageAt = t.LastMessageAt__c != null ? t.LastMessageAt__c.format('dd/MM/yyyy HH:mm') : '';
            dto.unreadCount = unreadByThread.containsKey(t.Id) ? unreadByThread.get(t.Id) : 0;
            dto.isRead      = dto.unreadCount == 0;
            CommunicatorMessage__c lastMsg = lastMessageByThread.get(t.Id);
            dto.lastMessageBody      = (lastMsg != null) ? lastMsg.Body__c : null;
            dto.lastIsSystemMessage  = (lastMsg != null) ? lastMsg.IsSystemMessage__c : null;
            dto.lastSenderName       = (lastMsg != null && lastMsg.Sender__r != null) ? lastMsg.Sender__r.Name : null;
            dto.lastSenderPhoto      = (lastMsg != null && lastMsg.Sender__r != null) ? lastMsg.Sender__r.SmallPhotoUrl : null;
            result.add(dto);
        }
        return result;
    }

    public static Opportunity resolveAuthorizedOpportunityForChatterHistory(Id threadId, Id expectedOpportunityId) {
        if (threadId == null || threadId.getSObjectType() != CommunicatorThread__c.SObjectType) {
            throw getInvalidChatterHistoryAccessException();
        }
        if (expectedOpportunityId != null && expectedOpportunityId.getSObjectType() != Opportunity.SObjectType) {
            throw getInvalidChatterHistoryAccessException();
        }

        ChatterHistoryAuthorizationReader reader = new ChatterHistoryAuthorizationReader();
        CommunicatorThread__c threadRecord = reader.getThread(threadId);
        if (threadRecord == null
            || threadRecord.Status__c == 'Archived'
            || threadRecord.RecordType__c == 'CommunicatorGroup__c'
            || String.isBlank(threadRecord.RecordId__c)) {
            throw getInvalidChatterHistoryAccessException();
        }

        Id resolvedOpportunityId = resolveAuthorizedOpportunityIdForChatterHistory(threadRecord, reader);
        if (resolvedOpportunityId == null) {
            throw getInvalidChatterHistoryAccessException();
        }
        if (expectedOpportunityId != null && expectedOpportunityId != resolvedOpportunityId) {
            throw getInvalidChatterHistoryAccessException();
        }

        return new Opportunity(Id = resolvedOpportunityId);
    }

    private static Id resolveAuthorizedOpportunityIdForChatterHistory(
        CommunicatorThread__c threadRecord,
        ChatterHistoryAuthorizationReader reader
    ) {
        if (threadRecord == null || threadRecord.Id == null || reader == null) return null;

        Id resolvedOpportunityId = reader.resolveOpportunityId(threadRecord.RecordId__c);
        if (resolvedOpportunityId == null) return null;

        if (reader.hasActiveParticipant(threadRecord.Id, UserInfo.getUserId())) {
            return resolvedOpportunityId;
        }

        Set<Id> accessibleOpportunityIds = getCardAccessibleOpportunityIdsForCurrentUser(
            new Set<Id>{ resolvedOpportunityId }
        );
        return accessibleOpportunityIds.contains(resolvedOpportunityId)
            ? resolvedOpportunityId
            : null;
    }

    private static Set<Id> getThreadIdsVisibleInCurrentUserList() {
        Id userId = UserInfo.getUserId();
        Set<Id> threadIds = new Set<Id>();
        for (CommunicatorParticipant__c participant : [
            SELECT Thread__c
            FROM   CommunicatorParticipant__c
            WHERE  User__c = :userId
            AND    IsActive__c = true
        ]) {
            threadIds.add(participant.Thread__c);
        }
        if (isCurrentUserSalesforcePlatform()) {
            threadIds.addAll(getEligibleThreadIdsForSalesforcePlatform());
        }
        return filterVisibleThreadIdsForCurrentUser(threadIds);
    }

    /**
     * @description Returns a paginated list of threads the current user participates in.
     * @param pageSize  Number of threads per page.
     * @param offsetVal Zero-based offset.
     * @param filter    'all' | 'read' | 'unread'
     */
    public static List<CommunicatorDTOs.ThreadListItemDTO> getThreadList(
        Integer pageSize, Integer offsetVal, String filter
    ) {
        Id      userId = UserInfo.getUserId();
        Integer sz     = (pageSize  != null && pageSize  > 0) ? pageSize  : 10;
        Integer off    = (offsetVal != null && offsetVal >= 0) ? offsetVal : 0;

        // Step 1 — threads where current user is an active participant
        List<CommunicatorParticipant__c> parts = [
            SELECT Thread__c FROM CommunicatorParticipant__c
            WHERE User__c = :userId AND IsActive__c = true
        ];

        Set<Id> threadIds = new Set<Id>();
        for (CommunicatorParticipant__c p : parts) threadIds.add(p.Thread__c);

        if (isCurrentUserSalesforcePlatform()) {
            threadIds.addAll(getEligibleThreadIdsForSalesforcePlatform());
        }
        if (threadIds.isEmpty()) return new List<CommunicatorDTOs.ThreadListItemDTO>();

        // Step 2 — thread IDs that have at least one unread notification for this user
        Set<Id> unreadThreadIds = new Set<Id>();
        for (AggregateResult ar : [
            SELECT Thread__c tid
            FROM   CommunicatorNotification__c
            WHERE  Recipient__c = :userId
            AND    IsRead__c    = false
            AND    Thread__c    IN :threadIds
            GROUP  BY Thread__c
        ]) {
            unreadThreadIds.add((Id) ar.get('tid'));
        }

        // Step 3 — determine which thread IDs to query based on filter
        Set<Id> filterIds;
        if (filter == 'unread') {
            if (unreadThreadIds.isEmpty()) return new List<CommunicatorDTOs.ThreadListItemDTO>();
            filterIds = unreadThreadIds;
        } else if (filter == 'read') {
            filterIds = new Set<Id>();
            for (Id tid : threadIds) {
                if (!unreadThreadIds.contains(tid)) filterIds.add(tid);
            }
            if (filterIds.isEmpty()) return new List<CommunicatorDTOs.ThreadListItemDTO>();
        } else {
            filterIds = threadIds;
        }

        // For Platform (assessoria) users: restrict threads to only those for
        // opportunities where the user's assessoria queue owns the AR.
        if (isCurrentUserSalesforcePlatform()) {
            filterIds = filterThreadIdsByAssessoriaAccess(filterIds);
            if (filterIds.isEmpty()) return new List<CommunicatorDTOs.ThreadListItemDTO>();
        }

        // Step 4 — fetch threads (exclude group threads – those belong to the Groups tab only)
        List<CommunicatorThread__c> threads = [
            SELECT Id, Name, RecordId__c, RecordType__c, Stage__c,
                   SubStatus__c, LastMessageAt__c
            FROM   CommunicatorThread__c
            WHERE  Id IN :filterIds
            AND    Status__c     != 'Archived'
            AND    RecordType__c != 'CommunicatorGroup__c'
            ORDER  BY LastMessageAt__c DESC NULLS LAST LIMIT :sz OFFSET :off
        ];
        if (threads.isEmpty()) return new List<CommunicatorDTOs.ThreadListItemDTO>();

        return buildThreadListCards(threads);
    }

    public static List<CommunicatorDTOs.ThreadListItemDTO> getThreadCardsByIdsPreservingOrder(List<Id> threadIds) {
        if (threadIds == null || threadIds.isEmpty()) {
            return new List<CommunicatorDTOs.ThreadListItemDTO>();
        }

        Set<Id> uniqueThreadIds = new Set<Id>(threadIds);
        Map<Id, CommunicatorThread__c> threadById = new Map<Id, CommunicatorThread__c>([
            SELECT Id, Name, RecordId__c, RecordType__c, Stage__c,
                   SubStatus__c, LastMessageAt__c
            FROM   CommunicatorThread__c
            WHERE  Id IN :uniqueThreadIds
            AND    Status__c     != 'Archived'
            AND    RecordType__c != 'CommunicatorGroup__c'
        ]);
        if (threadById.isEmpty()) {
            return new List<CommunicatorDTOs.ThreadListItemDTO>();
        }

        List<CommunicatorThread__c> orderedThreads = new List<CommunicatorThread__c>();
        Set<Id> addedThreadIds = new Set<Id>();
        for (Id threadId : threadIds) {
            if (threadId == null || addedThreadIds.contains(threadId)) continue;
            CommunicatorThread__c threadRecord = threadById.get(threadId);
            if (threadRecord == null) continue;
            orderedThreads.add(threadRecord);
            addedThreadIds.add(threadId);
        }

        return buildThreadListCards(orderedThreads);
    }

    public static List<CommunicatorDTOs.ThreadListItemDTO> getThreadCardsByRecentOrder(
        List<Id> recentThreadIds,
        Integer maxCount
    ) {
        Integer resultLimit = (maxCount != null && maxCount > 0) ? maxCount : 5;
        if (resultLimit > 2000) resultLimit = 2000;

        List<CommunicatorThread__c> orderedThreads = new List<CommunicatorThread__c>();
        Set<Id> addedThreadIds = new Set<Id>();
        Set<Id> seenOpportunityIds = new Set<Id>();

        if (recentThreadIds != null && !recentThreadIds.isEmpty()) {
            Set<Id> uniqueRecentThreadIds = new Set<Id>(recentThreadIds);
            Map<Id, CommunicatorThread__c> threadById = new Map<Id, CommunicatorThread__c>([
                SELECT Id, Name, RecordId__c, RecordType__c, Stage__c,
                       SubStatus__c, LastMessageAt__c
                FROM   CommunicatorThread__c
                WHERE  Id IN :uniqueRecentThreadIds
                AND    Status__c     != 'Archived'
                AND    RecordType__c != 'CommunicatorGroup__c'
            ]);

            for (Id threadId : recentThreadIds) {
                if (threadId == null || addedThreadIds.contains(threadId)) continue;
                CommunicatorThread__c threadRecord = threadById.get(threadId);
                if (threadRecord == null || String.isBlank(threadRecord.RecordId__c)) continue;
                Id opportunityId = resolveOpportunityIdForThreadRecord(threadRecord.RecordId__c);
                if (opportunityId == null || seenOpportunityIds.contains(opportunityId)) continue;

                orderedThreads.add(threadRecord);
                addedThreadIds.add(threadId);
                seenOpportunityIds.add(opportunityId);
                if (orderedThreads.size() >= resultLimit) {
                    return buildThreadListCards(orderedThreads);
                }
            }
        }

        Set<Id> visibleThreadIds = getThreadIdsVisibleInCurrentUserList();
        if (!visibleThreadIds.isEmpty()) {
            Integer fallbackLimit = resultLimit * 5;
            if (fallbackLimit > 2000) fallbackLimit = 2000;

            List<CommunicatorThread__c> fallbackThreads = [
                SELECT Id, Name, RecordId__c, RecordType__c, Stage__c,
                       SubStatus__c, LastMessageAt__c
                FROM   CommunicatorThread__c
                WHERE  Id IN :visibleThreadIds
                AND    Status__c     != 'Archived'
                AND    RecordType__c != 'CommunicatorGroup__c'
                ORDER  BY LastMessageAt__c DESC NULLS LAST, CreatedDate DESC
                LIMIT  :fallbackLimit
            ];

            for (CommunicatorThread__c threadRecord : fallbackThreads) {
                if (threadRecord == null || addedThreadIds.contains(threadRecord.Id)) continue;
                if (String.isBlank(threadRecord.RecordId__c)) continue;
                Id opportunityId = resolveOpportunityIdForThreadRecord(threadRecord.RecordId__c);
                if (opportunityId == null || seenOpportunityIds.contains(opportunityId)) continue;

                orderedThreads.add(threadRecord);
                addedThreadIds.add(threadRecord.Id);
                seenOpportunityIds.add(opportunityId);
                if (orderedThreads.size() >= resultLimit) break;
            }
        }

        return buildThreadListCards(orderedThreads);
    }

    private static List<CommunicatorDTOs.ThreadListItemDTO> buildThreadListCards(
        List<CommunicatorThread__c> threads
    ) {
        if (threads == null || threads.isEmpty()) {
            return new List<CommunicatorDTOs.ThreadListItemDTO>();
        }

        Id userId = UserInfo.getUserId();

        // Step 5 — per-thread unread count for this user (only for fetched threads)
        Set<Id> fetchedIds = new Set<Id>();
        for (CommunicatorThread__c t : threads) fetchedIds.add(t.Id);

        Map<Id, Integer> unreadByThread = new Map<Id, Integer>();
        for (AggregateResult ar : [
            SELECT Thread__c tid, COUNT(Id) cnt
            FROM   CommunicatorNotification__c
            WHERE  Thread__c    IN :fetchedIds
            AND    Recipient__c = :userId
            AND    IsRead__c    = false
            GROUP  BY Thread__c
        ]) {
            unreadByThread.put((Id) ar.get('tid'), Integer.valueOf(ar.get('cnt')));
        }

        // Step 5b — last sender per thread (for socket presence display)
        Map<Id, Id> lastSenderByThread = new Map<Id, Id>();
        for (CommunicatorMessage__c msg : [
            SELECT Thread__c, Sender__c
            FROM   CommunicatorMessage__c
            WHERE  Thread__c IN :fetchedIds
            ORDER  BY SentAt__c DESC
            LIMIT  200
        ]) {
            if (!lastSenderByThread.containsKey(msg.Thread__c)) {
                lastSenderByThread.put(msg.Thread__c, msg.Sender__c);
            }
        }

        // Step 6 — batch-query record names grouped by object type
        // When RecordType__c is blank, resolve the type from the Id prefix.
        Map<String, Set<Id>> idsByType = new Map<String, Set<Id>>();
        Map<Id, String> resolvedTypeByThreadId = new Map<Id, String>();
        for (CommunicatorThread__c t : threads) {
            if (String.isBlank(t.RecordId__c)) continue;
            String recType = t.RecordType__c;
            if (String.isBlank(recType)) {
                try {
                    Id sfId = (Id) t.RecordId__c;
                    recType = sfId.getSObjectType().getDescribe().getName();
                } catch (Exception e) { continue; }
            }
            resolvedTypeByThreadId.put(t.Id, recType);
            if (!idsByType.containsKey(recType)) idsByType.put(recType, new Set<Id>());
            try { idsByType.get(recType).add((Id) t.RecordId__c); } catch (Exception e) {}
        }
        Map<Id, String> nameById = new Map<Id, String>();
        Map<Id, Id> repasseOpportunityIdByRepasseId = new Map<Id, Id>();
        for (String objType : idsByType.keySet()) {
            try {
                Set<Id> ids = idsByType.get(objType);
                if (objType == 'Opportunity') {
                    for (Opportunity opportunityRecord : CommunicatorOpportunityDataService.getOpportunitiesByIds(ids)) {
                        nameById.put(opportunityRecord.Id, opportunityRecord.Name);
                    }
                } else if (objType == 'Repasse__c') {
                    Map<Id, Repasse__c> repassesById = CommunicatorRepasseService.getRepassesByIds(ids);
                    for (Repasse__c repasseRecord : repassesById.values()) {
                        if (repasseRecord == null || repasseRecord.Id == null) continue;
                        nameById.put(repasseRecord.Id, repasseRecord.Name);
                        if (repasseRecord.Oportunidade__c != null) {
                            repasseOpportunityIdByRepasseId.put(repasseRecord.Id, repasseRecord.Oportunidade__c);
                        }
                    }
                } else {
                    List<SObject> recs = Database.query(
                        'SELECT Id, Name FROM ' + objType + ' WHERE Id IN :ids'
                    );
                    for (SObject r : recs) nameById.put(r.Id, (String) r.get('Name'));
                }
            } catch (Exception e) { /* skip inaccessible types */ }
        }
        // Fallback: re-query Opportunity by ID prefix for any thread whose name wasn't resolved.
        // This handles cases where RecordType__c has a stale/wrong value that doesn't match RecordId__c.
        Set<Id> unresolvedOppIds = new Set<Id>();
        for (CommunicatorThread__c t : threads) {
            Id recId;
            try { recId = (Id) t.RecordId__c; } catch (Exception e) { continue; }
            if (recId != null && !nameById.containsKey(recId)
                    && String.valueOf(recId).startsWith('006')) {
                unresolvedOppIds.add(recId);
            }
        }
        if (!unresolvedOppIds.isEmpty()) {
            try {
                for (Opportunity unresolvedOpportunity : CommunicatorOpportunityDataService.getOpportunitiesByIds(unresolvedOppIds)) {
                    nameById.put(unresolvedOpportunity.Id, unresolvedOpportunity.Name);
                }
            } catch (Exception e) { /* skip if inaccessible */ }
        }

        // Step 6b — batch-query the CURRENT stage of each linked record, grouped by object type.
        // Reuses the same idsByType map built in Step 6; one SOQL per object type.
        Map<Id, String> currentStageById = new Map<Id, String>();

        // Opportunity stage is fetched via the without sharing service so that users who
        // only have thread access via an @mention (no direct record sharing) still see the
        // correct phase in the history list card — consistent with how names are resolved above.
        if (idsByType.containsKey('Opportunity')) {
            for (Opportunity opp : CommunicatorOpportunityDataService.getOpportunitiesByIds(idsByType.get('Opportunity'))) {
                if (opp.StageName != null) currentStageById.put(opp.Id, opp.StageName);
            }
        }

        for (String objType : idsByType.keySet()) {
            if (objType == 'Opportunity') continue; // already handled above
            String statusField = CommunicatorConfigService.getStatusFieldName(objType);
            if (String.isBlank(statusField)) continue;
            try {
                Set<Id> ids = idsByType.get(objType);
                List<SObject> recs = Database.query(
                    'SELECT Id, ' + statusField + ' FROM ' + objType + ' WHERE Id IN :ids'
                );
                for (SObject r : recs) {
                    Object val = r.get(statusField);
                    if (val != null) currentStageById.put(r.Id, String.valueOf(val));
                }
            } catch (Exception e) { /* skip inaccessible types or unconfigured fields */ }
        }

        // Step 6c — classify threads as Repasse or Opportunity without an extra SOQL.
        //           Repasse-phase threads use the 7 canonical macro-phase labels as Stage__c.
        //           Opportunity-stage threads use Opportunity stage names.
        //           Classifying at the thread level lets the LWC etapa filter show
        //           Opportunity-stage threads (e.g. “Contrato Assinado”) separately from
        //           Repasse-phase threads (“Aguardando início”) for the same Opportunity.
        Set<String> repasseMacroPhases = new Set<String>{
            'aguardando inicio', 'formulario', 'conferencia de dossie',
            'pendencias', 'assinatura do repasse', 'retencao', 'triagem', 'outros'
        };

        // Repasse cards aligned with communicatorHistoryPage current phase behavior.
        Map<Id, String> repassePhaseByOppId = new Map<Id, String>();
        Map<Id, Repasse__c> latestRepasseByOppId = new Map<Id, Repasse__c>();
        Set<Id> opportunityIds = idsByType.containsKey('Opportunity')
            ? idsByType.get('Opportunity')
            : new Set<Id>();
        if (!opportunityIds.isEmpty()) {
            latestRepasseByOppId = getVisibleLatestRepassesByOpportunityIds(opportunityIds);
            for (Id oppId : latestRepasseByOppId.keySet()) {
                Repasse__c latestRepasse = latestRepasseByOppId.get(oppId);
                String repasseSinteseName = CommunicatorRepassePhaseHelper.getRepasseSinteseName(latestRepasse);
                if (String.isBlank(repasseSinteseName)) continue;
                String macroPhase = CommunicatorRepassePhaseHelper.getMacroPhase(repasseSinteseName);
                if (String.isNotBlank(macroPhase)) repassePhaseByOppId.put(oppId, macroPhase);
            }
        }
        Boolean isSFPlatformUser = isCurrentUserSalesforcePlatform();
        // Step 7 — build DTOs
        List<CommunicatorDTOs.ThreadListItemDTO> result = new List<CommunicatorDTOs.ThreadListItemDTO>();
        for (CommunicatorThread__c t : threads) {
            CommunicatorDTOs.ThreadListItemDTO dto = new CommunicatorDTOs.ThreadListItemDTO();
            dto.threadId      = t.Id;
            dto.threadName    = t.Name;
            dto.recordId      = t.RecordId__c;
            dto.recordType    = resolvedTypeByThreadId.containsKey(t.Id)
                                ? resolvedTypeByThreadId.get(t.Id)
                                : t.RecordType__c;
            dto.stageName     = t.Stage__c;
            dto.statusLabel   = t.SubStatus__c;
            dto.lastMessageAt = t.LastMessageAt__c != null
                                ? t.LastMessageAt__c.format('dd/MM/yyyy HH:mm')
                                : '';
            dto.unreadCount   = unreadByThread.containsKey(t.Id) ? unreadByThread.get(t.Id) : 0;
            dto.isRead        = dto.unreadCount == 0;
            Id recId = null;
            try { recId = (Id) t.RecordId__c; } catch (Exception e) {}
            dto.recordName    = (recId != null && nameById.containsKey(recId))
                                ? nameById.get(recId)
                                : t.Name;
            if (recId != null && repasseOpportunityIdByRepasseId.containsKey(recId)) {
                dto.repasseOpportunityId = String.valueOf(repasseOpportunityIdByRepasseId.get(recId));
            }
            Boolean hasVisibleRepasseForOpportunity =
                recId != null && latestRepasseByOppId != null && latestRepasseByOppId.containsKey(recId);
            dto.hasRepasse    = String.isNotBlank(t.Stage__c)
                                && repasseMacroPhases.contains(normalizeCommunicatorStage(t.Stage__c));
            if (isSFPlatformUser && t.RecordType__c == 'Opportunity' && !hasVisibleRepasseForOpportunity) {
                dto.hasRepasse = false;
            }
            if (isSFPlatformUser && dto.hasRepasse && recId != null && hasVisibleRepasseForOpportunity) {
                Repasse__c repasse = latestRepasseByOppId.get(recId);
                if (repasse != null) {
                    dto.recordName = repasse.Name;
                }
            } else if (isSFPlatformUser && dto.hasRepasse && recId != null && String.valueOf(recId).startsWith('a') && dto.recordType == 'Repasse__c') {
                // Already returns the name from nameById
            }
            dto.currentStage  = (recId != null && currentStageById.containsKey(recId))
                                ? currentStageById.get(recId)
                                : dto.stageName;
            if (dto.hasRepasse && recId != null && repassePhaseByOppId.containsKey(recId)) {
                dto.currentStage = repassePhaseByOppId.get(recId);
            }
            dto.lastSenderId  = lastSenderByThread.containsKey(t.Id)
                                ? String.valueOf(lastSenderByThread.get(t.Id))
                                : null;
            result.add(dto);
        }
        return result;
    }

    /**
     * @description Returns the total count of threads the current user participates in.
     * @param filter 'all' | 'read' | 'unread'
     */
    public static Integer getThreadCount(String filter) {
        Id userId = UserInfo.getUserId();
        List<CommunicatorParticipant__c> parts = [
            SELECT Thread__c FROM CommunicatorParticipant__c
            WHERE User__c = :userId AND IsActive__c = true
        ];

        Set<Id> threadIds = new Set<Id>();
        for (CommunicatorParticipant__c p : parts) threadIds.add(p.Thread__c);

        if (isCurrentUserSalesforcePlatform()) {
            threadIds.addAll(getEligibleThreadIdsForSalesforcePlatform());
        }
        if (threadIds.isEmpty()) return 0;

        // Compute unread thread IDs from CommunicatorNotification__c
        Set<Id> unreadThreadIds = new Set<Id>();
        for (AggregateResult ar : [
            SELECT Thread__c tid
            FROM   CommunicatorNotification__c
            WHERE  Recipient__c = :userId
            AND    IsRead__c    = false
            AND    Thread__c    IN :threadIds
            GROUP  BY Thread__c
        ]) {
            unreadThreadIds.add((Id) ar.get('tid'));
        }

        if (isCurrentUserSalesforcePlatform()) {
            threadIds = filterThreadIdsByAssessoriaAccess(threadIds);
            if (threadIds.isEmpty()) return 0;
            Set<Id> filteredUnread = new Set<Id>();
            for (Id tid : unreadThreadIds) {
                if (threadIds.contains(tid)) filteredUnread.add(tid);
            }
            unreadThreadIds = filteredUnread;
        }

        if (filter == 'unread') {
            if (unreadThreadIds.isEmpty()) return 0;
            return [SELECT COUNT() FROM CommunicatorThread__c
                    WHERE Id IN :unreadThreadIds AND Status__c != 'Archived'
                    AND RecordType__c != 'CommunicatorGroup__c'];
        } else if (filter == 'read') {
            Set<Id> readIds = new Set<Id>();
            for (Id tid : threadIds) {
                if (!unreadThreadIds.contains(tid)) readIds.add(tid);
            }
            if (readIds.isEmpty()) return 0;
            return [SELECT COUNT() FROM CommunicatorThread__c
                    WHERE Id IN :readIds AND Status__c != 'Archived'
                    AND RecordType__c != 'CommunicatorGroup__c'];
        }
        return [SELECT COUNT() FROM CommunicatorThread__c
                WHERE Id IN :threadIds AND Status__c != 'Archived'
                AND RecordType__c != 'CommunicatorGroup__c'];
    }

    /**
     * @description Validates that the given record Id is accessible to the current user.
     *              Uses a generic SOQL approach via Schema to avoid hardcoding object types.
     */
    private static void validateRecordAccess(String recordId) {
        if (String.isBlank(recordId)) {
            throw new CommunicatorException('Record ID cannot be blank.');
        }

        // Extract SObject type from the Id prefix
        try {
            Id sfId = (Id) recordId;
            Schema.SObjectType sObjectType = sfId.getSObjectType();
            String objectName = sObjectType.getDescribe().getName();

            // Dynamic SOQL to check read access without hardcoding the object
            Integer count = Database.countQuery(
                'SELECT COUNT() FROM ' + objectName + ' WHERE Id = :sfId'
            );
            if (count == 0) {
                throw new CommunicatorException('Record not found or not accessible.');
            }
        } catch (CommunicatorException ce) {
            throw ce;
        } catch (Exception ex) {
            throw new CommunicatorException('Invalid Record ID: ' + ex.getMessage());
        }
    }

    private static Boolean canAccessRecordOrParticipatesInThread(String recordId) {
        if (String.isBlank(recordId)) return false;
        try {
            validateRecordAccess(recordId);
            if (isCurrentUserSalesforcePlatform()) {
                Id resolvedOppId = resolveOpportunityIdForAssessoriaAccess(recordId);
                if (resolvedOppId != null) {
                    return isAssessoriaAllowedOpportunity(resolvedOppId)
                        || isAssessoriaAllowedViaGroupMention(resolvedOppId);
                }
                return false;
            }
            return true;
        } catch (Exception ex) {
            if (isCurrentUserSalesforcePlatform()) {
                Id resolvedOppId = resolveOpportunityIdForAssessoriaAccess(recordId);
                if (resolvedOppId != null) {
                    return isAssessoriaAllowedViaGroupMention(resolvedOppId);
                }
                return false;
            }
            Id userId = UserInfo.getUserId();
            Integer participantCount = [
                SELECT COUNT()
                FROM CommunicatorParticipant__c
                WHERE User__c = :userId
                AND IsActive__c = true
                AND Thread__r.RecordId__c = :recordId
                AND Thread__r.Status__c != 'Archived'
            ];
            return participantCount > 0;
        }
    }

    /**
     * @description Returns the subset of threadIds that are visible in the current user's
     *              thread list. For Salesforce Platform (assessoria) users, applies the
     *              same filterThreadIdsByAssessoriaAccess filter used by getThreadList and
     *              getThreadCount, keeping badge counts in sync with visible cards.
     *              For all other license types, returns the input set unchanged.
     */
    public static Set<Id> filterVisibleThreadIdsForCurrentUser(Set<Id> threadIds) {
        if (threadIds == null || threadIds.isEmpty()) return new Set<Id>();
        if (!isCurrentUserSalesforcePlatform()) return threadIds;
        return filterThreadIdsByAssessoriaAccess(threadIds);
    }

    /** Returns active conventional threads that the current user's chat list exposes. */
    public static Set<Id> getVisibleConventionalThreadIdsForCurrentUser(Set<Id> requestedThreadIds) {
        if (requestedThreadIds == null || requestedThreadIds.isEmpty()) return new Set<Id>();
        Set<Id> visibleThreadIds = getThreadIdsVisibleInCurrentUserList();
        visibleThreadIds.retainAll(requestedThreadIds);
        if (visibleThreadIds.isEmpty()) return new Set<Id>();

        Set<Id> result = new Set<Id>();
        for (CommunicatorThread__c threadRecord : [
            SELECT Id
            FROM CommunicatorThread__c
            WHERE Id IN :visibleThreadIds
            AND Status__c != 'Archived'
            AND RecordType__c != 'CommunicatorGroup__c'
        ]) {
            result.add(threadRecord.Id);
        }
        return result;
    }

    public static Set<Id> filterRecentlyViewedThreadIdsForCurrentUser(Set<Id> threadIds) {
        if (threadIds == null || threadIds.isEmpty()) return new Set<Id>();
        if (!isCurrentUserSalesforcePlatform()) return threadIds;

        Map<Id, Id> opportunityIdByThreadId = new Map<Id, Id>();
        Set<Id> opportunityIds = new Set<Id>();
        for (CommunicatorThread__c threadRecord : [
            SELECT Id, RecordId__c
            FROM CommunicatorThread__c
            WHERE Id IN :threadIds
            AND Status__c != 'Archived'
            AND RecordType__c != 'CommunicatorGroup__c'
        ]) {
            Id opportunityId = resolveOpportunityIdForAssessoriaAccess(threadRecord.RecordId__c);
            if (opportunityId == null) continue;
            opportunityIds.add(opportunityId);
            opportunityIdByThreadId.put(threadRecord.Id, opportunityId);
        }
        if (opportunityIds.isEmpty()) return new Set<Id>();

        Set<Id> visibleOpportunityIds = getVisibleOpportunityCardIdsForCurrentUser(opportunityIds);
        if (visibleOpportunityIds.isEmpty()) return new Set<Id>();

        Set<Id> allowedThreadIds = new Set<Id>();
        for (Id threadId : opportunityIdByThreadId.keySet()) {
            if (visibleOpportunityIds.contains(opportunityIdByThreadId.get(threadId))) {
                allowedThreadIds.add(threadId);
            }
        }
        return allowedThreadIds;
    }

    private static Set<Id> filterThreadIdsByAssessoriaAccess(Set<Id> threadIds) {
        Set<Id> allowedThreadIds = new Set<Id>();
        if (threadIds == null || threadIds.isEmpty()) return allowedThreadIds;
        Set<Id> mentionedThreadIds = getGroupMentionedThreadIdsForCurrentUser();
        for (Id threadId : threadIds) {
            if (mentionedThreadIds.contains(threadId)) {
                allowedThreadIds.add(threadId);
            }
        }

        Set<Id> opportunityIds = new Set<Id>();
        Map<Id, Id> opportunityIdByThreadId = new Map<Id, Id>();
        for (CommunicatorThread__c threadRecord : [
            SELECT Id, RecordId__c
            FROM CommunicatorThread__c
            WHERE Id IN :threadIds
            AND Status__c != 'Archived'
            AND RecordType__c != 'CommunicatorGroup__c'
        ]) {
            Id oppId = resolveOpportunityIdForAssessoriaAccess(threadRecord.RecordId__c);
            if (oppId == null) continue;
            opportunityIds.add(oppId);
            opportunityIdByThreadId.put(threadRecord.Id, oppId);
        }

        if (opportunityIds.isEmpty()) return allowedThreadIds;
        Set<Id> eligibleOppIds = getEligibleOpportunityIdsForSalesforcePlatform(opportunityIds);
        if (eligibleOppIds.isEmpty()) return allowedThreadIds;

        for (Id threadId : opportunityIdByThreadId.keySet()) {
            if (eligibleOppIds.contains(opportunityIdByThreadId.get(threadId))) {
                allowedThreadIds.add(threadId);
            }
        }
        return allowedThreadIds;
    }

    private static Set<Id> getMentionAccessibleOpportunityIdsForCurrentUser() {
        Set<Id> opportunityIds = new Set<Id>();
        Set<Id> mentionedThreadIds = getGroupMentionedThreadIdsForCurrentUser();
        if (mentionedThreadIds.isEmpty()) return opportunityIds;

        for (CommunicatorThread__c threadRecord : [
            SELECT Id, RecordId__c, RecordType__c
            FROM CommunicatorThread__c
            WHERE Id IN :mentionedThreadIds
            AND Status__c != 'Archived'
            AND RecordType__c != 'CommunicatorGroup__c'
            LIMIT 2000
        ]) {
            Id opportunityId = resolveOpportunityIdForAssessoriaAccess(threadRecord.RecordId__c);
            if (opportunityId != null) {
                opportunityIds.add(opportunityId);
            }
        }
        return opportunityIds;
    }

    private static Id resolveOpportunityIdForAssessoriaAccess(String recordId) {
        if (String.isBlank(recordId)) return null;
        try {
            Id sfId = (Id) recordId;
            String objectApiName = sfId.getSObjectType().getDescribe().getName();
            if (objectApiName == 'Opportunity') return sfId;
            if (objectApiName == 'Repasse__c') {
                Map<Id, Repasse__c> repassesById = CommunicatorRepasseService.getRepassesByIds(new Set<Id>{ sfId });
                Repasse__c repasse = repassesById.get(sfId);
                if (repasse == null || !isRepasseVisibleForCurrentUser(repasse)) {
                    return null;
                }
                return repasse.Oportunidade__c;
            }
        } catch (Exception e) {}
        return null;
    }

    public static Id resolveOpportunityIdForThreadRecord(String recordId) {
        return resolveOpportunityIdForAssessoriaAccess(recordId);
    }

    public static Boolean canCurrentUserRestoreViewedThread(Id threadId, String expectedRecordId) {
        if (threadId == null) return false;

        List<CommunicatorThread__c> threadRows = [
            SELECT Id, RecordId__c
            FROM CommunicatorThread__c
            WHERE Id = :threadId
            AND Status__c != 'Archived'
            AND RecordType__c != 'CommunicatorGroup__c'
            LIMIT 1
        ];
        if (threadRows.isEmpty()) return false;

        Id opportunityId = resolveOpportunityIdForAssessoriaAccess(threadRows[0].RecordId__c);
        if (opportunityId == null) return false;

        if (!String.isBlank(expectedRecordId)) {
            try {
                if ((Id) expectedRecordId != opportunityId) return false;
            } catch (Exception e) {
                return false;
            }
        }

        if (!isCurrentUserSalesforcePlatform()) return true;
        Set<Id> visibleOpportunityIds = getVisibleOpportunityCardIdsForCurrentUser(
            new Set<Id>{ opportunityId }
        );
        return visibleOpportunityIds.contains(opportunityId);
    }

    /** Validates the record, thread, and referenced message or system FeedItem for notification navigation. */
    public static CommunicatorDTOs.NotificationNavigationDTO getNotificationNavigationContext(
        String threadIdValue,
        String messageIdValue,
        String targetRecordIdValue
    ) {
        CommunicatorDTOs.NotificationNavigationDTO result = new CommunicatorDTOs.NotificationNavigationDTO();
        if (String.isBlank(threadIdValue) || String.isBlank(messageIdValue) || String.isBlank(targetRecordIdValue)) return result;

        Id threadId;
        Id targetId;
        Id targetRecordId;
        try {
            threadId = (Id) threadIdValue;
            targetId = (Id) messageIdValue;
            targetRecordId = (Id) targetRecordIdValue;
        } catch (Exception ex) {
            return result;
        }
        if (threadId.getSObjectType() != CommunicatorThread__c.SObjectType
            || CommunicatorBroadcastService.isBroadcastThread(threadId)) return result;

        validateRecordAccess(String.valueOf(targetRecordId));
        Boolean visibleThread = false;
        for (CommunicatorDTOs.ThreadListItemDTO candidate : getThreadsForRecord(String.valueOf(targetRecordId))) {
            try {
                if ((Id) candidate.threadId == threadId
                    && (Id) candidate.recordId == targetRecordId
                    && candidate.recordType != 'CommunicatorGroup__c') {
                    visibleThread = true;
                    break;
                }
            } catch (Exception ex) {
                // Ignore malformed legacy rows.
            }
        }
        if (!visibleThread) return result;

        Boolean validTarget = false;
        if (targetId.getSObjectType() == CommunicatorMessage__c.SObjectType) {
            validTarget = ![
                SELECT Id FROM CommunicatorMessage__c
                WHERE Id = :targetId AND Thread__c = :threadId LIMIT 1
            ].isEmpty();
        } else if (targetId.getSObjectType() == FeedItem.SObjectType) {
            List<FeedItem> feedItems = [
                SELECT Id, Body
                FROM FeedItem
                WHERE Id = :targetId AND ParentId = :threadId AND Type = 'TextPost'
                LIMIT 1
            ];
            validTarget = !feedItems.isEmpty()
                && CommunicatorSystemEventService.isSystemEventPost(feedItems[0].Body);
        }
        if (!validTarget) return result;

        result.threadId = String.valueOf(threadId);
        result.recordId = String.valueOf(targetRecordId);
        result.messageId = String.valueOf(targetId);
        return result;
    }

    /** Determines whether the current user may follow the selected non-archived thread. */
    public static Boolean canFollowThread(Id threadId) {
        if (threadId == null || UserInfo.getUserType() == 'Guest') return false;
        ChatterHistoryAuthorizationReader reader = new ChatterHistoryAuthorizationReader();
        CommunicatorThread__c thread = reader.getThread(threadId);
        if (thread == null || thread.Status__c == 'Archived') return false;
        if (thread.RecordType__c == 'CommunicatorGroup__c') {
            if (reader.hasActiveParticipant(threadId, UserInfo.getUserId())) return true;
            if (!String.isBlank(thread.RecordId__c)
                && CommunicatorGroupService.getMemberUserIds(new Set<Id>{ (Id) thread.RecordId__c }).contains(UserInfo.getUserId())) return true;
            return [SELECT COUNT() FROM CommunicatorThread__c WHERE Id = :threadId] > 0;
        }
        if (reader.hasActiveParticipant(threadId, UserInfo.getUserId())) {
            return filterVisibleThreadIdsForCurrentUser(new Set<Id>{ threadId }).contains(threadId);
        }
        return canAccessRecordOrParticipatesInThread(thread.RecordId__c);
    }

    private static Boolean isAssessoriaAllowedOpportunity(Id opportunityId) {
        if (opportunityId == null) return false;
        Set<Id> eligibleIds = getEligibleOpportunityIdsForSalesforcePlatform(new Set<Id>{ opportunityId });
        return eligibleIds.contains(opportunityId);
    }

    /**
     * @description Returns thread ids that contain at least one message mentioning
     *              a group where the current user is an active member.
     */
    public static Set<Id> getGroupMentionedThreadIdsForCurrentUser() {
        if (groupMentionedThreadIdsCacheInitialized) return new Set<Id>(groupMentionedThreadIdsCache);
        groupMentionedThreadIdsCache = new GroupMentionAccessHelper().getThreadIdsForUserGroups(UserInfo.getUserId());
        groupMentionedThreadIdsCacheInitialized = true;
        return new Set<Id>(groupMentionedThreadIdsCache);
    }

    @TestVisible
    private static void clearGroupMentionCache() {
        groupMentionedThreadIdsCache = null;
        groupMentionedThreadIdsCacheInitialized = false;
    }

    /**
     * @description Checks whether the current user can access an Opportunity
     *              through group mention context.
     */
    public static Boolean isAssessoriaAllowedViaGroupMention(Id opportunityId) {
        if (opportunityId == null) return false;
        Set<Id> mentionedThreadIds = getGroupMentionedThreadIdsForCurrentUser();
        if (mentionedThreadIds.isEmpty()) return false;

        Integer matchCount = [
            SELECT COUNT()
            FROM   CommunicatorThread__c
            WHERE  Id IN :mentionedThreadIds
            AND    RecordId__c = :String.valueOf(opportunityId)
            AND    Status__c != 'Archived'
            AND    RecordType__c != 'CommunicatorGroup__c'
        ];
        return matchCount > 0;
    }

    private static CommunicatorException getInvalidChatterHistoryAccessException() {
        return new CommunicatorException('Record not found or not accessible.');
    }

    /**
     * @description Queries group memberships and group-mentioned thread IDs without
     *              sharing enforcement. Required because the assessoria user may not
     *              yet have direct record access — this computes whether they SHOULD
     *              have access via a group @mention.
     *              Access is dynamic: revoked automatically when the user is removed
     *              from the group or the group is deleted.
     */
    private without sharing class GroupMentionAccessHelper {
        Set<Id> getThreadIdsForUserGroups(Id userId) {
            Set<Id> groupIds = new Set<Id>();
            for (CommunicatorGroupMember__c m : [
                SELECT Group__c
                FROM   CommunicatorGroupMember__c
                WHERE  User__c = :userId
                AND    Group__r.IsActive__c = true
            ]) {
                if (m.Group__c != null) groupIds.add(m.Group__c);
            }
            if (groupIds.isEmpty()) return new Set<Id>();

            Set<Id> threadIds = new Set<Id>();
            for (CommunicatorMessage__c msg : [
                SELECT Thread__c, MentionedGroupIds__c
                FROM   CommunicatorMessage__c
                WHERE  HasMention__c = true
                AND    Thread__r.Status__c != 'Archived'
                ORDER  BY SentAt__c DESC
                LIMIT  2000
            ]) {
                if (String.isBlank(msg.MentionedGroupIds__c) || msg.Thread__c == null) continue;
                Set<Id> mentionedGroupIds = CommunicatorMentionService.deserializeUserIds(msg.MentionedGroupIds__c);
                for (Id gId : mentionedGroupIds) {
                    if (groupIds.contains(gId)) {
                        threadIds.add(msg.Thread__c);
                        break;
                    }
                }
            }
            return threadIds;
        }
    }

    private without sharing class ChatterHistoryAuthorizationReader {
        CommunicatorThread__c getThread(Id threadId) {
            List<CommunicatorThread__c> rows = [
                SELECT Id, RecordId__c, RecordType__c, Status__c
                FROM CommunicatorThread__c
                WHERE Id = :threadId
                LIMIT 1
            ];
            return rows.isEmpty() ? null : rows[0];
        }

        Boolean hasActiveParticipant(Id threadId, Id userId) {
            if (threadId == null || userId == null) {
                return false;
            }

            return [
                SELECT COUNT()
                FROM CommunicatorParticipant__c
                WHERE Thread__c = :threadId
                AND User__c = :userId
                AND IsActive__c = true
            ] > 0;
        }

        Id resolveOpportunityId(String recordId) {
            if (String.isBlank(recordId)) {
                return null;
            }

            Id sourceRecordId;
            try {
                sourceRecordId = (Id) recordId;
            } catch (Exception ex) {
                return null;
            }

            Id opportunityId;
            Schema.SObjectType sourceType = sourceRecordId.getSObjectType();
            if (sourceType == Opportunity.SObjectType) {
                opportunityId = sourceRecordId;
            } else if (sourceType == Repasse__c.SObjectType) {
                List<Repasse__c> repasses = [
                    SELECT Oportunidade__c
                    FROM Repasse__c
                    WHERE Id = :sourceRecordId
                    LIMIT 1
                ];
                opportunityId = repasses.isEmpty() ? null : repasses[0].Oportunidade__c;
            } else if (sourceType == Quote.SObjectType) {
                List<Quote> quotes = [
                    SELECT OpportunityId
                    FROM Quote
                    WHERE Id = :sourceRecordId
                    LIMIT 1
                ];
                opportunityId = quotes.isEmpty() ? null : quotes[0].OpportunityId;
            } else if (sourceType == AnaliseFinanceira__c.SObjectType) {
                List<AnaliseFinanceira__c> analises = [
                    SELECT Oportunidade__c
                    FROM AnaliseFinanceira__c
                    WHERE Id = :sourceRecordId
                    LIMIT 1
                ];
                opportunityId = analises.isEmpty() ? null : analises[0].Oportunidade__c;
            } else if (sourceType == AprovacaoBancaria__c.SObjectType) {
                List<AprovacaoBancaria__c> aprovacoes = [
                    SELECT AnaliseCredito__r.Oportunidade__c
                    FROM AprovacaoBancaria__c
                    WHERE Id = :sourceRecordId
                    LIMIT 1
                ];
                opportunityId = aprovacoes.isEmpty()
                    ? null
                    : aprovacoes[0].AnaliseCredito__r == null
                        ? null
                        : aprovacoes[0].AnaliseCredito__r.Oportunidade__c;
            }

            if (opportunityId == null) {
                return null;
            }

            List<Opportunity> opportunities = [
                SELECT Id
                FROM Opportunity
                WHERE Id = :opportunityId
                LIMIT 1
            ];
            return opportunities.isEmpty() ? null : opportunities[0].Id;
        }
    }

    private static Set<Id> getEligibleThreadIdsForSalesforcePlatform() {
        Set<Id> visibleAssessoriaIds = getVisibleAssessoriaIdsForCurrentUser();
        if (visibleAssessoriaIds != null && !visibleAssessoriaIds.isEmpty()) {
            Set<Id> result = new Set<Id>();
            Map<Id, Id> opportunityIdByThreadId = new Map<Id, Id>();
            Set<Id> opportunityIds = new Set<Id>();
            for (CommunicatorThread__c threadRecord : [
                SELECT Id, RecordId__c
                FROM CommunicatorThread__c
                WHERE Status__c != 'Archived'
                AND RecordType__c != 'CommunicatorGroup__c'
                LIMIT 2000
            ]) {
                Id oppId = resolveOpportunityIdForAssessoriaAccess(threadRecord.RecordId__c);
                if (oppId == null) continue;
                opportunityIds.add(oppId);
                opportunityIdByThreadId.put(threadRecord.Id, oppId);
            }
            if (!opportunityIds.isEmpty()) {
                Set<Id> visibleOpportunityIds = CommunicatorOpportunityAccessService.getVisibleOpportunityIds(opportunityIds);
                for (Id threadId : opportunityIdByThreadId.keySet()) {
                    if (visibleOpportunityIds.contains(opportunityIdByThreadId.get(threadId))) {
                        result.add(threadId);
                    }
                }
            }
            result.addAll(getGroupMentionedThreadIdsForCurrentUser());
            return removeDeactivatedParticipantThreads(result);
        }

        Set<Id> result = new Set<Id>();
        Set<Id> userQueueIds = getCurrentUserQueueIds();

        if (!userQueueIds.isEmpty()) {
            Set<Id> eligibleOppIds = new Set<Id>();
            for (Opportunity opportunityRecord : [
                SELECT Id
                FROM Opportunity
                WHERE ApuracaoRenda__c != null
                AND ApuracaoRenda__r.OwnerId IN :userQueueIds
                LIMIT 2000
            ]) {
                eligibleOppIds.add(opportunityRecord.Id);
            }
            if (!eligibleOppIds.isEmpty()) {
                for (CommunicatorThread__c threadRecord : [
                    SELECT Id, RecordId__c
                    FROM CommunicatorThread__c
                    WHERE Status__c != 'Archived'
                    AND RecordType__c != 'CommunicatorGroup__c'
                    AND RecordId__c IN :eligibleOppIds
                    LIMIT 2000
                ]) {
                    result.add(threadRecord.Id);
                }
            }
        }
        result.addAll(getGroupMentionedThreadIdsForCurrentUser());
        return removeDeactivatedParticipantThreads(result);
    }

    /**
     * @description Removes threads where the current user's participant was deactivated
     *              (IsActive__c = false) and the user has no independent access path to
     *              the linked opportunity. Threads with no participant record are unaffected.
     */
    private static Set<Id> removeDeactivatedParticipantThreads(Set<Id> threadIds) {
        if (threadIds == null || threadIds.isEmpty()) return threadIds;

        Set<Id> deactivatedThreadIds = new Set<Id>();
        for (CommunicatorParticipant__c p : [
            SELECT Thread__c
            FROM   CommunicatorParticipant__c
            WHERE  User__c     = :UserInfo.getUserId()
            AND    Thread__c   IN :threadIds
            AND    IsActive__c = false
        ]) {
            deactivatedThreadIds.add(p.Thread__c);
        }
        if (deactivatedThreadIds.isEmpty()) return threadIds;

        Map<Id, Id> oppIdByDeactivatedThread = new Map<Id, Id>();
        for (CommunicatorThread__c t : [
            SELECT Id, RecordId__c
            FROM   CommunicatorThread__c
            WHERE  Id IN :deactivatedThreadIds
        ]) {
            try {
                Id recId = (Id) t.RecordId__c;
                if (recId != null) oppIdByDeactivatedThread.put(t.Id, recId);
            } catch (Exception e) {}
        }

        Set<Id> independentlyAccessibleThreadIds = new Set<Id>();
        if (!oppIdByDeactivatedThread.isEmpty()) {
            Set<Id> deactivatedOppIds = new Set<Id>(oppIdByDeactivatedThread.values());
            Set<Id> independentOppIds = new Set<Id>();

            Set<Id> visibleAssessoriaIds = getVisibleAssessoriaIdsForCurrentUser();
            if (visibleAssessoriaIds != null && !visibleAssessoriaIds.isEmpty()) {
                independentOppIds.addAll(
                    CommunicatorOpportunityAccessService.getVisibleOpportunityIds(deactivatedOppIds)
                );
            } else {
                Set<Id> userQueueIds = getCurrentUserQueueIds();
                independentOppIds.addAll(getOpportunityIdsWithApuracaoRenda(deactivatedOppIds, userQueueIds));
                independentOppIds.addAll(getOpportunityIdsWithAprovacaoBancaria(deactivatedOppIds, independentOppIds));
            }

            for (Id threadId : oppIdByDeactivatedThread.keySet()) {
                if (independentOppIds.contains(oppIdByDeactivatedThread.get(threadId))) {
                    independentlyAccessibleThreadIds.add(threadId);
                }
            }
        }

        Set<Id> threadsToRemove = new Set<Id>(deactivatedThreadIds);
        threadsToRemove.removeAll(independentlyAccessibleThreadIds);
        threadIds.removeAll(threadsToRemove);
        return threadIds;
    }

    @TestVisible
    private static Set<Id> getVisibleOpportunityCardIdsForCurrentUser(Set<Id> opportunityIds) {
        if (opportunityIds == null || opportunityIds.isEmpty()) return new Set<Id>();
        if (!isCurrentUserSalesforcePlatform()) return new Set<Id>(opportunityIds);

        Set<Id> visibleOpportunityIds = getEligibleOpportunityIdsForSalesforcePlatform(opportunityIds);
        Set<Id> mentionOpportunityIds = getMentionAccessibleOpportunityIdsForCurrentUser();
        if (!mentionOpportunityIds.isEmpty()) {
            mentionOpportunityIds.retainAll(opportunityIds);
            visibleOpportunityIds.addAll(mentionOpportunityIds);
        }
        return visibleOpportunityIds;
    }

    @TestVisible
    private static Set<Id> getCardAccessibleOpportunityIdsForCurrentUser(Set<Id> opportunityIds) {
        if (opportunityIds == null || opportunityIds.isEmpty()) return new Set<Id>();
        if (isCurrentUserSalesforcePlatform()) {
            return getVisibleOpportunityCardIdsForCurrentUser(opportunityIds);
        }
        return CommunicatorOpportunityAccessService.getVisibleOpportunityIds(opportunityIds);
    }

    public static String resolveOpportunityIdIfRepasse(String recordId) {
        if (String.isBlank(recordId)) {
            return recordId;
        }

        try {
            Id sfId = (Id) recordId;
            if (sfId.getSObjectType().getDescribe().getName() != 'Repasse__c') {
                return recordId;
            }
        } catch (Exception e) {
            return recordId;
        }

        return resolveOpportunityIdFromRepasse(recordId);
    }

    private static String resolveOpportunityIdFromRepasse(String recordId) {
        Id repasseId = (Id) recordId;
        Map<Id, Repasse__c> repassesById = CommunicatorRepasseService.getRepassesByIds(new Set<Id>{ repasseId });
        Repasse__c repasse = repassesById.get(repasseId);

        if (repasse == null || repasse.Oportunidade__c == null) {
            return recordId;
        }

        if (isCurrentUserSalesforcePlatform() && !isRepasseVisibleForCurrentUser(repasse)) {
            return recordId;
        }

        Set<Id> visibleOppIds = CommunicatorOpportunityAccessService.getVisibleOpportunityIds(
            new Set<Id>{ repasse.Oportunidade__c }
        );
        if (!visibleOppIds.contains(repasse.Oportunidade__c)) {
            throw new CommunicatorException('Record not found or not accessible.');
        }

        return String.valueOf(repasse.Oportunidade__c);
    }

    public static String resolveOpportunityIdForAnaliseFinanceira(Id afId) {
        if (afId == null) return null;
        List<AnaliseFinanceira__c> rows = [
            SELECT Oportunidade__c
            FROM   AnaliseFinanceira__c
            WHERE  Id = :afId
            LIMIT  1
        ];
        if (rows.isEmpty() || rows[0].Oportunidade__c == null) return null;
        Set<Id> visible = CommunicatorOpportunityAccessService.getVisibleOpportunityIds(
            new Set<Id>{ rows[0].Oportunidade__c }
        );
        if (!visible.contains(rows[0].Oportunidade__c)) {
            throw new CommunicatorException('Record not found or not accessible.');
        }
        return String.valueOf(rows[0].Oportunidade__c);
    }

    private static String resolveOpportunityIdForAprovacaoBancaria(Id aprovacaoBancariaId) {
        if (aprovacaoBancariaId == null) return null;
        List<AprovacaoBancaria__c> rows = [
            SELECT AnaliseCredito__c
            FROM   AprovacaoBancaria__c
            WHERE  Id = :aprovacaoBancariaId
            LIMIT  1
        ];
        if (rows.isEmpty() || rows[0].AnaliseCredito__c == null) return null;
        return resolveOpportunityIdForAnaliseFinanceira(rows[0].AnaliseCredito__c);
    }

    private static String resolveOpportunityIdForQuote(Id quoteId) {
        if (quoteId == null) return null;
        List<Quote> rows = [
            SELECT OpportunityId
            FROM   Quote
            WHERE  Id = :quoteId
            LIMIT  1
        ];
        if (rows.isEmpty() || rows[0].OpportunityId == null) return null;
        Set<Id> visible = CommunicatorOpportunityAccessService.getVisibleOpportunityIds(
            new Set<Id>{ rows[0].OpportunityId }
        );
        if (!visible.contains(rows[0].OpportunityId)) {
            throw new CommunicatorException('Record not found or not accessible.');
        }
        return String.valueOf(rows[0].OpportunityId);
    }

    public static String resolveOpportunityIdForRecord(Id recordId, String objectApiName) {
        if (recordId == null) return null;
        String resolvedType = String.isNotBlank(objectApiName)
            ? objectApiName
            : recordId.getSObjectType().getDescribe().getName();
        if (resolvedType == 'Opportunity')          return String.valueOf(recordId);
        if (resolvedType == 'AnaliseFinanceira__c') return resolveOpportunityIdForAnaliseFinanceira(recordId);
        if (resolvedType == 'Repasse__c')           return resolveOpportunityIdFromRepasse(String.valueOf(recordId));
        if (resolvedType == 'AprovacaoBancaria__c') return resolveOpportunityIdForAprovacaoBancaria(recordId);
        if (resolvedType == 'Quote')                return resolveOpportunityIdForQuote(recordId);
        return null;
    }

    // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    // Group thread
    // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

    /**
     * @description Returns the singleton active thread for a group, creating one if it does not exist.
     *              RecordType__c = 'CommunicatorGroup__c', RecordId__c = groupId, Stage__c = 'group'.
     */
    /**
     * @description Returns phase info for a list of source thread IDs.
     *              canReply is true only when the thread's Stage__c matches the opportunity's
     *              current phase (accounting for Repasse macro-phases).
     */
    public static List<CommunicatorDTOs.SourceThreadInfoDTO> getSourceThreadsInfo(List<Id> threadIds) {
        if (threadIds == null || threadIds.isEmpty()) return new List<CommunicatorDTOs.SourceThreadInfoDTO>();

        List<CommunicatorThread__c> threads = [
            SELECT Id, Stage__c, RecordId__c
            FROM   CommunicatorThread__c
            WHERE  Id IN :threadIds
        ];

        Set<Id> oppIds = new Set<Id>();
        for (CommunicatorThread__c t : threads) {
            if (String.isBlank(t.RecordId__c)) continue;
            try {
                Id rid = (Id) t.RecordId__c;
                if (rid.getSObjectType().getDescribe().getName() == 'Opportunity') oppIds.add(rid);
            } catch (Exception e) {}
        }

        Map<Id, String> effectiveStageByOppId = new Map<Id, String>();
        Map<Id, String> oppNameById = new Map<Id, String>();
        Map<Id, CommunicatorDTOs.OpportunityRelatedRefsDTO> refsByOppId =
            new Map<Id, CommunicatorDTOs.OpportunityRelatedRefsDTO>();
        if (!oppIds.isEmpty()) {
            for (Opportunity opp : [
                SELECT Id, Name, StageName
                FROM Opportunity
                WHERE Id IN :oppIds
            ]) {
                oppNameById.put(opp.Id, opp.Name);
                effectiveStageByOppId.put(opp.Id, opp.StageName);
            }

            Map<Id, Repasse__c> latestByOpp = getVisibleLatestRepassesByOpportunityIds(oppIds);
            for (Id oppId : latestByOpp.keySet()) {
                Repasse__c repasse = latestByOpp.get(oppId);
                String repasseSinteseName = CommunicatorRepassePhaseHelper.getRepasseSinteseName(repasse);
                if (String.isBlank(repasseSinteseName)) continue;
                String macroPhase = CommunicatorRepassePhaseHelper.getMacroPhase(repasseSinteseName);
                if (String.isNotBlank(macroPhase)) effectiveStageByOppId.put(oppId, macroPhase);
            }

            refsByOppId = getOpportunityRelatedRefs(new List<Id>(oppIds));

            // Group members may lack direct Opportunity access (with sharing filtered them out).
            // Read StageName without sharing so canReply is based on the real phase, not null.
            Set<Id> missingOppIds = new Set<Id>(oppIds);
            missingOppIds.removeAll(effectiveStageByOppId.keySet());
            if (Test.isRunningTest() && simulateInaccessibleOppIdsForTest != null) {
                for (Id oid : simulateInaccessibleOppIdsForTest) {
                    effectiveStageByOppId.remove(oid);
                    missingOppIds.add(oid);
                }
            }
            if (!missingOppIds.isEmpty()) {
                Map<Id, String> bypassStages = new Map<Id, String>();
                for (Opportunity opp : new OppStageBypassReader().getByIds(missingOppIds)) {
                    bypassStages.put(opp.Id, opp.StageName);
                    oppNameById.put(opp.Id, opp.Name);
                }
                Map<Id, Repasse__c> bypassRepasse = getVisibleLatestRepassesByOpportunityIds(missingOppIds);
                for (Id oid : missingOppIds) {
                    String stage = bypassStages.get(oid);
                    if (String.isBlank(stage)) continue;
                    Repasse__c rep = bypassRepasse.get(oid);
                    if (rep != null) {
                        String sintese = CommunicatorRepassePhaseHelper.getRepasseSinteseName(rep);
                        String macro   = String.isNotBlank(sintese)
                            ? CommunicatorRepassePhaseHelper.getMacroPhase(sintese) : '';
                        if (String.isNotBlank(macro)) stage = macro;
                    }
                    effectiveStageByOppId.put(oid, stage);
                }
            }
        }

        List<CommunicatorDTOs.SourceThreadInfoDTO> result = new List<CommunicatorDTOs.SourceThreadInfoDTO>();
        for (CommunicatorThread__c t : threads) {
            CommunicatorDTOs.SourceThreadInfoDTO dto = new CommunicatorDTOs.SourceThreadInfoDTO();
            dto.threadId  = t.Id;
            dto.stageName = t.Stage__c;
            dto.canReply  = false;
            if (String.isNotBlank(t.RecordId__c) && String.isNotBlank(t.Stage__c)) {
                try {
                    Id rid = (Id) t.RecordId__c;
                    dto.opportunityId = String.valueOf(rid);
                    dto.opportunityName = oppNameById.get(rid);
                    CommunicatorDTOs.OpportunityRelatedRefsDTO refs = refsByOppId.get(rid);
                    dto.arId = (refs != null) ? refs.arId : null;
                    dto.arName = (refs != null) ? refs.arName : null;
                    dto.abId = (refs != null) ? refs.abId : null;
                    dto.abName = (refs != null) ? refs.abName : null;
                    dto.quoteId = (refs != null) ? refs.quoteId : null;
                    dto.quoteName = (refs != null) ? refs.quoteName : null;
                    dto.resolvedRefType = (refs != null) ? refs.resolvedRefType : null;
                    dto.resolvedRefId = (refs != null) ? refs.resolvedRefId : null;
                    dto.resolvedRefName = (refs != null) ? refs.resolvedRefName : null;
                    dto.resolvedRefObjectApiName = (refs != null) ? refs.resolvedRefObjectApiName : null;
                    String current = effectiveStageByOppId.get(rid);
                    if (String.isNotBlank(current)) dto.stageName = current;
                    dto.canReply = String.isNotBlank(current) && t.Stage__c == current;
                } catch (Exception e) {}
            }
            result.add(dto);
        }
        return result;
    }

    /**
     * @description Returns AR / AB / Cotação refs for each Opportunity Id.
     *              AB is resolved by the most recent AprovacaoBancaria__c linked to
     *              Opportunity.AnaliseCredito__c.
     */
    public static Map<Id, CommunicatorDTOs.OpportunityRelatedRefsDTO> getOpportunityRelatedRefs(List<Id> opportunityIds) {
        Map<Id, CommunicatorDTOs.OpportunityRelatedRefsDTO> result =
            new Map<Id, CommunicatorDTOs.OpportunityRelatedRefsDTO>();
        if (opportunityIds == null || opportunityIds.isEmpty()) return result;

        Set<Id> oppIds = new Set<Id>(opportunityIds);
        Set<Id> visibleAssessoriaIds = getVisibleAssessoriaIdsForCurrentUser();
        if (visibleAssessoriaIds != null && !visibleAssessoriaIds.isEmpty()) {
            oppIds.retainAll(CommunicatorOpportunityAccessService.getVisibleOpportunityIds(oppIds));
            if (oppIds.isEmpty()) return result;
        }
        Map<Id, String> stageByOppId = new Map<Id, String>();
        Map<Id, Id> analiseCreditoByOppId = new Map<Id, Id>();
        Map<Id, Id> oppIdByAnaliseCreditoId = new Map<Id, Id>();
        Set<Id> analiseCreditoIds = new Set<Id>();

        for (Opportunity opp : CommunicatorOpportunityDataService.getOpportunitiesWithRelatedRefsByIds(oppIds)) {
            CommunicatorDTOs.OpportunityRelatedRefsDTO dto = new CommunicatorDTOs.OpportunityRelatedRefsDTO();
            dto.arId = (opp.ApuracaoRenda__c != null) ? String.valueOf(opp.ApuracaoRenda__c) : null;
            dto.arName = (opp.ApuracaoRenda__r != null) ? opp.ApuracaoRenda__r.Name : null;
            dto.quoteId = (opp.SyncedQuoteId != null) ? String.valueOf(opp.SyncedQuoteId) : null;
            dto.quoteName = (opp.SyncedQuote != null)
                ? (String.isNotBlank(opp.SyncedQuote.QuoteNumber) ? opp.SyncedQuote.QuoteNumber : opp.SyncedQuote.Name)
                : null;
            dto.quoteCount = (opp.SyncedQuoteId != null) ? 1 : 0;
            result.put(opp.Id, dto);
            stageByOppId.put(opp.Id, opp.StageName);

            if (opp.AnaliseCredito__c != null) {
                analiseCreditoByOppId.put(opp.Id, opp.AnaliseCredito__c);
                oppIdByAnaliseCreditoId.put(opp.AnaliseCredito__c, opp.Id);
                analiseCreditoIds.add(opp.AnaliseCredito__c);
            }
        }

        populateLatestQuotes(result, oppIds);

        if (!analiseCreditoIds.isEmpty()) {
            for (AprovacaoBancaria__c ab : CommunicatorOpportunityDataService.getAprovacaoBancariaByAnaliseCreditoIds(analiseCreditoIds)) {
                Id oppId = oppIdByAnaliseCreditoId.get(ab.AnaliseCredito__c);
                if (oppId == null) continue;
                CommunicatorDTOs.OpportunityRelatedRefsDTO dto = result.get(oppId);
                if (dto == null || String.isNotBlank(dto.abId)) continue;
                dto.abId = String.valueOf(ab.Id);
                dto.abName = ab.Name;
            }
        }

        Map<Id, String> analiseCreditoNameById = new Map<Id, String>();
        if (!analiseCreditoIds.isEmpty()) {
            for (AnaliseFinanceira__c analiseCredito : CommunicatorOpportunityDataService.getAnaliseFinanceiraByIds(analiseCreditoIds)) {
                analiseCreditoNameById.put(analiseCredito.Id, analiseCredito.Name);
            }
        }

        for (Id oppId : result.keySet()) {
            CommunicatorDTOs.OpportunityRelatedRefsDTO dto = result.get(oppId);
            Id analiseCreditoId = analiseCreditoByOppId.get(oppId);
            if (dto == null || analiseCreditoId == null) {
                applyResolvedRef(dto, stageByOppId.get(oppId));
                continue;
            }
            dto.analiseCreditoId = String.valueOf(analiseCreditoId);
            dto.analiseCreditoName = analiseCreditoNameById.get(analiseCreditoId);
            applyResolvedRef(dto, stageByOppId.get(oppId));
        }

        return result;
    }

    private static void populateLatestQuotes(
        Map<Id, CommunicatorDTOs.OpportunityRelatedRefsDTO> refsByOpportunityId,
        Set<Id> opportunityIds
    ) {
        if (refsByOpportunityId == null || refsByOpportunityId.isEmpty() || opportunityIds == null || opportunityIds.isEmpty()) {
            return;
        }

        Map<Id, Integer> quoteCountByOpportunityId = new Map<Id, Integer>();
        Set<Id> firstQuoteSetByOpportunityId = new Set<Id>();
        for (Quote quote : CommunicatorOpportunityDataService.getQuotesByOpportunityIds(opportunityIds)) {
            if (quote.OpportunityId == null || !refsByOpportunityId.containsKey(quote.OpportunityId)) continue;
            quoteCountByOpportunityId.put(quote.OpportunityId, (quoteCountByOpportunityId.get(quote.OpportunityId) == null ? 0 : quoteCountByOpportunityId.get(quote.OpportunityId)) + 1);
            if (firstQuoteSetByOpportunityId.contains(quote.OpportunityId)) continue;
            CommunicatorDTOs.OpportunityRelatedRefsDTO dto = refsByOpportunityId.get(quote.OpportunityId);
            dto.quoteId = String.valueOf(quote.Id);
            dto.quoteName = String.isNotBlank(quote.QuoteNumber) ? quote.QuoteNumber : quote.Name;
            firstQuoteSetByOpportunityId.add(quote.OpportunityId);
        }

        for (Id opportunityId : refsByOpportunityId.keySet()) {
            if (!quoteCountByOpportunityId.containsKey(opportunityId)) continue;
            refsByOpportunityId.get(opportunityId).quoteCount = quoteCountByOpportunityId.get(opportunityId);
        }
    }

    private static void applyResolvedRef(CommunicatorDTOs.OpportunityRelatedRefsDTO dto, String stageName) {
        if (dto == null) return;
        clearResolvedRef(dto);
        String normalizedStage = normalizeCommunicatorStage(stageName);
        if (normalizedStage.contains('negoci')) {
            setResolvedRef(dto, 'quote', dto.quoteId, dto.quoteName, 'Quote');
            return;
        }
        if (normalizedStage.contains('analise de credito')) {
            if (String.isNotBlank(dto.abId)) {
                setResolvedRef(dto, 'ab', dto.abId, dto.abName, 'AprovacaoBancaria__c');
                return;
            }
            setResolvedRef(dto, 'ar', dto.arId, dto.arName, 'AnaliseFinanceira__c');
            return;
        }
        if (normalizedStage.contains('montagem') || normalizedStage.contains('apuracao de renda') || normalizedStage.contains('analise de renda')) {
            if (String.isNotBlank(dto.abId)) {
                setResolvedRef(dto, 'ab', dto.abId, dto.abName, 'AprovacaoBancaria__c');
                return;
            }
            setResolvedRef(dto, 'ar', dto.arId, dto.arName, 'AnaliseFinanceira__c');
        }
    }

    private static void setResolvedRef(
        CommunicatorDTOs.OpportunityRelatedRefsDTO dto,
        String refType,
        String refId,
        String refName,
        String objectApiName
    ) {
        if (dto == null || String.isBlank(refId) || String.isBlank(refName)) return;
        dto.resolvedRefType = refType;
        dto.resolvedRefId = refId;
        dto.resolvedRefName = refName;
        dto.resolvedRefObjectApiName = objectApiName;
    }

    private static void clearResolvedRef(CommunicatorDTOs.OpportunityRelatedRefsDTO dto) {
        if (dto == null) return;
        dto.resolvedRefType = null;
        dto.resolvedRefId = null;
        dto.resolvedRefName = null;
        dto.resolvedRefObjectApiName = null;
    }

    private static String normalizeCommunicatorStage(String value) {
        String normalized = String.valueOf(value == null ? '' : value).toLowerCase();
        normalized = normalized.replace('\u00e1', 'a').replace('\u00e0', 'a').replace('\u00e2', 'a').replace('\u00e3', 'a').replace('\u00e4', 'a');
        normalized = normalized.replace('\u00e9', 'e').replace('\u00ea', 'e').replace('\u00e8', 'e').replace('\u00eb', 'e');
        normalized = normalized.replace('\u00ed', 'i').replace('\u00ec', 'i').replace('\u00ee', 'i').replace('\u00ef', 'i');
        normalized = normalized.replace('\u00f3', 'o').replace('\u00f2', 'o').replace('\u00f4', 'o').replace('\u00f5', 'o').replace('\u00f6', 'o');
        normalized = normalized.replace('\u00fa', 'u').replace('\u00f9', 'u').replace('\u00fb', 'u').replace('\u00fc', 'u');
        normalized = normalized.replace('\u00e7', 'c'); // \u00e7 \u2192 c (e.g. Apura\u00e7\u00e3o \u2192 apuracao)
        return normalized;
    }

    private static CommunicatorThread__c getLatestRepassePhaseThreadByRecordId(String recordId) {
        if (String.isBlank(recordId)) return null;
        if (isCurrentUserSalesforcePlatform()) {
            try {
                Id opportunityId = (Id) recordId;
                Map<Id, Repasse__c> visibleLatestByOppId = getVisibleLatestRepassesByOpportunityIds(
                    new Set<Id>{ opportunityId }
                );
                if (!visibleLatestByOppId.containsKey(opportunityId)) {
                    return null;
                }
            } catch (Exception e) {
                return null;
            }
        }
        Set<String> repasseMacroPhases = new Set<String>{
            'aguardando inicio', 'formulario', 'conferencia de dossie',
            'pendencias', 'assinatura do repasse', 'retencao', 'triagem', 'outros'
        };
        for (CommunicatorThread__c threadRecord : [
            SELECT Id, Name, RecordId__c, RecordType__c, Status__c, Stage__c,
                   SubStatus__c, Reason__c, ExternalId__c, LastMessageAt__c, UnreadCount__c
            FROM   CommunicatorThread__c
            WHERE  RecordId__c = :recordId
            AND    Status__c  != 'Archived'
            ORDER  BY LastMessageAt__c DESC NULLS LAST
        ]) {
            if (String.isBlank(threadRecord.Stage__c)) continue;
            if (repasseMacroPhases.contains(normalizeCommunicatorStage(threadRecord.Stage__c))) {
                return threadRecord;
            }
        }
        return null;
    }

    // Reads Opportunity Name and StageName without sharing so group members who lack
    // direct Opportunity access still get the correct canReply value and opportunity
    // name in getSourceThreadsInfo.
    private without sharing class OppStageBypassReader {
        List<Opportunity> getByIds(Set<Id> oppIds) {
            if (oppIds == null || oppIds.isEmpty()) return new List<Opportunity>();
            return [SELECT Id, Name, StageName FROM Opportunity WHERE Id IN :oppIds];
        }
    }

    private without sharing class OpportunityKeywordBypassReader {
        List<Opportunity> getOpportunitiesByIds(Set<Id> opportunityIds) {
            if (opportunityIds == null || opportunityIds.isEmpty()) return new List<Opportunity>();
            String cpfField = hasPersonAccountCpfField() ? 'Account.CPF__pc, ' : '';
            String soql = 'SELECT Id, Name, StageName, ' + cpfField
                + 'ApuracaoRenda__r.Name, AnaliseCredito__c, AnaliseCredito__r.Name'
                + ' FROM Opportunity WHERE Id IN :opportunityIds';
            List<Opportunity> opportunities = new List<Opportunity>();
            for (SObject row : Database.query(soql)) {
                opportunities.add((Opportunity) row);
            }
            return opportunities;
        }
    }

    private without sharing class ApuracaoPresenceBypassReader {
        List<Opportunity> getOpportunitiesByIds(Set<Id> opportunityIds) {
            if (opportunityIds == null || opportunityIds.isEmpty()) return new List<Opportunity>();
            return [
                SELECT Id, ApuracaoRenda__c
                FROM Opportunity
                WHERE Id IN :opportunityIds
                AND ApuracaoRenda__c != null
            ];
        }

        List<AnaliseFinanceira__c> getApuracoesByIds(Set<Id> apuracaoIds) {
            if (apuracaoIds == null || apuracaoIds.isEmpty()) return new List<AnaliseFinanceira__c>();
            return [
                SELECT Id, AnalistaResponsavel__c, DataHoraInicio__c, DataHoraTermino__c, Status__c, StatusAprovacao__c
                FROM AnaliseFinanceira__c
                WHERE Id IN :apuracaoIds
            ];
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Notification access filter (per-recipient, for Salesforce bell)
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description From a set of Salesforce Platform (assessoria) user IDs, returns only
     *              those who have actual visible access to the thread — via group @mention
     *              or AR/AB queue ownership. Used to prevent the Salesforce bell from
     *              firing for assessoria users who would see no card in the communicator.
     *
     *              Non-Platform users must NOT be passed here; they are always eligible
     *              and should be kept in the notification set by the caller.
     */
    public static Set<Id> getAssessoriaUsersWithThreadAccess(Id threadId, Set<Id> platformUserIds) {
        return getAssessoriaUsersWithThreadAccess(threadId, platformUserIds, new Set<Id>());
    }

    public static Set<Id> getAssessoriaUsersWithThreadAccess(
        Id threadId,
        Set<Id> platformUserIds,
        Set<Id> directlyMentionedPlatformUserIds
    ) {
        if (threadId == null || platformUserIds == null || platformUserIds.isEmpty()) return new Set<Id>();
        return new AssessoriaNotificationFilter(directlyMentionedPlatformUserIds).getEligible(threadId, platformUserIds);
    }

    /**
     * @description Bulk variant of the notification access filter. It preloads thread,
     *              group-mention, and group-member data for the whole batch before applying
     *              the existing per-thread AR/AB and repasse access rules.
     */
    public static Map<Id, Set<Id>> getAssessoriaUsersWithThreadAccessBulk(
        Map<Id, Set<Id>> platformUserIdsByThread,
        Map<Id, Set<Id>> directlyMentionedPlatformUserIdsByThread
    ) {
        Map<Id, Set<Id>> eligibleByThread = new Map<Id, Set<Id>>();
        if (platformUserIdsByThread == null || platformUserIdsByThread.isEmpty()) return eligibleByThread;

        Set<Id> threadIds = new Set<Id>();
        Set<Id> candidateUserIds = new Set<Id>();
        for (Id threadId : platformUserIdsByThread.keySet()) {
            if (threadId == null) continue;
            threadIds.add(threadId);
            Set<Id> candidateIds = platformUserIdsByThread.get(threadId);
            if (candidateIds != null) candidateUserIds.addAll(candidateIds);
        }
        if (threadIds.isEmpty() || candidateUserIds.isEmpty()) return eligibleByThread;

        Set<Id> missingThreadIds = new Set<Id>();
        for (Id threadId : threadIds) {
            if (!notificationThreadByIdCache.containsKey(threadId)) missingThreadIds.add(threadId);
        }
        if (!missingThreadIds.isEmpty()) {
            for (CommunicatorThread__c thread : [
                SELECT Id, RecordId__c, RecordType__c, Stage__c
                FROM CommunicatorThread__c
                WHERE Id IN :missingThreadIds
            ]) {
                notificationThreadByIdCache.put(thread.Id, thread);
            }
            for (Id threadId : missingThreadIds) {
                if (!notificationThreadByIdCache.containsKey(threadId)) notificationThreadByIdCache.put(threadId, null);
            }
        }

        Set<Id> threadsMissingMentions = new Set<Id>();
        for (Id threadId : threadIds) {
            if (!mentionedGroupIdsByThreadIdCache.containsKey(threadId)) threadsMissingMentions.add(threadId);
        }
        if (!threadsMissingMentions.isEmpty()) {
            new AssessoriaNotificationFilter(new Set<Id>()).preloadMentionGroups(threadsMissingMentions);
        }

        Set<Id> mentionedGroupIds = new Set<Id>();
        for (Id threadId : threadIds) {
            Set<Id> cachedGroupIds = mentionedGroupIdsByThreadIdCache.get(threadId);
            if (cachedGroupIds != null) mentionedGroupIds.addAll(cachedGroupIds);
        }
        Map<Id, Set<Id>> eligibleGroupMembersByThread = new Map<Id, Set<Id>>();
        if (!mentionedGroupIds.isEmpty()) {
            Map<Id, Set<Id>> candidateGroupIdsByThread = new Map<Id, Set<Id>>();
            for (Id threadId : threadIds) {
                Set<Id> threadGroupIds = mentionedGroupIdsByThreadIdCache.get(threadId);
                if (threadGroupIds != null && !threadGroupIds.isEmpty()) {
                    candidateGroupIdsByThread.put(threadId, threadGroupIds);
                }
            }
            eligibleGroupMembersByThread = new AssessoriaNotificationFilter(new Set<Id>())
                .getMentionedGroupMembers(candidateGroupIdsByThread, candidateUserIds);
        }

        preloadBulkNotificationAccessData(threadIds, candidateUserIds);

        for (Id threadId : threadIds) {
            Set<Id> threadUsers = platformUserIdsByThread.get(threadId);
            if (threadUsers == null || threadUsers.isEmpty()) {
                eligibleByThread.put(threadId, new Set<Id>());
                continue;
            }
            Set<Id> initialEligible = new Set<Id>();
            Set<Id> directlyMentioned = directlyMentionedPlatformUserIdsByThread == null
                ? null
                : directlyMentionedPlatformUserIdsByThread.get(threadId);
            if (directlyMentioned != null) initialEligible.addAll(directlyMentioned);
            if (eligibleGroupMembersByThread.containsKey(threadId)) {
                initialEligible.addAll(eligibleGroupMembersByThread.get(threadId));
            }
            eligibleByThread.put(
                threadId,
                new AssessoriaNotificationFilter(new Set<Id>()).getEligible(threadId, threadUsers, initialEligible)
            );
        }
        return eligibleByThread;
    }

    /**
     * @description Without-sharing helper so that GroupMember / CommunicatorGroupMember__c /
     *              Opportunity / AnaliseFinanceira__c records are visible regardless of the
     *              sender's sharing context when evaluating recipients' access.
     */
    private without sharing class AssessoriaNotificationFilter {
        private final Set<Id> directlyMentionedPlatformUserIds;

        AssessoriaNotificationFilter(Set<Id> directlyMentionedPlatformUserIds) {
            this.directlyMentionedPlatformUserIds = directlyMentionedPlatformUserIds == null
                ? new Set<Id>()
                : new Set<Id>(directlyMentionedPlatformUserIds);
        }

        void preloadMentionGroups(Set<Id> threadIds) {
            Map<Id, Set<Id>> groupsByThreadId = new Map<Id, Set<Id>>();
            Integer messageLimit = remainingQueryRowBudget();
            List<CommunicatorMessage__c> messages = [
                SELECT Thread__c, MentionedGroupIds__c
                FROM CommunicatorMessage__c
                WHERE Thread__c IN :threadIds AND HasMention__c = true
                LIMIT :messageLimit
            ];
            if (messages.size() == messageLimit) {
                throw new NotificationAccessVolumeException('O filtro de notificações excedeu o limite de leitura de menções.');
            }
            for (CommunicatorMessage__c message : messages) {
                if (String.isBlank(message.MentionedGroupIds__c)) continue;
                if (!groupsByThreadId.containsKey(message.Thread__c)) groupsByThreadId.put(message.Thread__c, new Set<Id>());
                groupsByThreadId.get(message.Thread__c).addAll(
                    CommunicatorMentionService.deserializeUserIds(message.MentionedGroupIds__c)
                );
            }
            for (Id threadId : threadIds) {
                mentionedGroupIdsByThreadIdCache.put(
                    threadId,
                    groupsByThreadId.containsKey(threadId) ? groupsByThreadId.get(threadId) : new Set<Id>()
                );
            }
        }

        Map<Id, Set<Id>> getMentionedGroupMembers(
            Map<Id, Set<Id>> groupIdsByThreadId,
            Set<Id> candidateUserIds
        ) {
            Map<Id, Set<Id>> usersByGroupId = new Map<Id, Set<Id>>();
            Set<Id> groupIds = new Set<Id>();
            for (Set<Id> threadGroupIds : groupIdsByThreadId.values()) groupIds.addAll(threadGroupIds);
            if (!groupIds.isEmpty() && !candidateUserIds.isEmpty()) {
                Integer memberLimit = remainingQueryRowBudget();
                List<CommunicatorGroupMember__c> members = [
                    SELECT Group__c, User__c
                    FROM CommunicatorGroupMember__c
                    WHERE Group__c IN :groupIds
                        AND User__c IN :candidateUserIds
                        AND Group__r.IsActive__c = true
                    LIMIT :memberLimit
                ];
                if (members.size() == memberLimit) {
                    throw new NotificationAccessVolumeException('O filtro de notificações excedeu o limite de leitura de membros.');
                }
                for (CommunicatorGroupMember__c member : members) {
                    if (member.User__c == null) continue;
                    if (!usersByGroupId.containsKey(member.Group__c)) usersByGroupId.put(member.Group__c, new Set<Id>());
                    usersByGroupId.get(member.Group__c).add(member.User__c);
                }
            }
            Map<Id, Set<Id>> usersByThreadId = new Map<Id, Set<Id>>();
            for (Id threadId : groupIdsByThreadId.keySet()) {
                Set<Id> users = new Set<Id>();
                for (Id groupId : groupIdsByThreadId.get(threadId)) {
                    if (usersByGroupId.containsKey(groupId)) users.addAll(usersByGroupId.get(groupId));
                }
                usersByThreadId.put(threadId, users);
            }
            return usersByThreadId;
        }

        private Integer remainingQueryRowBudget() {
            Integer budget = Limits.getLimitQueryRows() - Limits.getQueryRows() - 1;
            if (budget <= 0) {
                throw new NotificationAccessVolumeException('Não há limite de linhas disponível para avaliar acesso às notificações.');
            }
            return budget;
        }

        Set<Id> getEligible(Id threadId, Set<Id> platformUserIds) {
            return getEligible(threadId, platformUserIds, null);
        }

        Set<Id> getEligible(Id threadId, Set<Id> platformUserIds, Set<Id> preloadedEligible) {
            Set<Id> eligible = new Set<Id>();
            if (preloadedEligible != null) {
                eligible.addAll(preloadedEligible);
                eligible.retainAll(platformUserIds);
            }
            if (!directlyMentionedPlatformUserIds.isEmpty()) {
                Set<Id> directlyMentionedEligible = new Set<Id>(platformUserIds);
                directlyMentionedEligible.retainAll(directlyMentionedPlatformUserIds);
                eligible.addAll(directlyMentionedEligible);
            }

            // — Step 1: group @mention access ────────────────────────────────
            Set<Id> mentionedGroupIds = preloadedEligible == null
                ? getMentionedCommunicatorGroupIds(threadId)
                : new Set<Id>();
            if (!mentionedGroupIds.isEmpty()) {
                for (CommunicatorGroupMember__c m : [
                    SELECT User__c
                    FROM   CommunicatorGroupMember__c
                    WHERE  Group__c IN :mentionedGroupIds
                    AND    User__c  IN :platformUserIds
                    AND    Group__r.IsActive__c = true
                ]) {
                    if (m.User__c != null) eligible.add(m.User__c);
                }
            }

            Set<Id> remaining = new Set<Id>(platformUserIds);
            remaining.removeAll(eligible);
            if (remaining.isEmpty()) return eligible;

            ThreadNotificationContext threadContext = getThreadNotificationContext(threadId);
            if (threadContext == null || threadContext.opportunityId == null) return eligible;

            if (threadContext.isRepasseContext && threadContext.repasseAssessoriaId != null) {
                eligible.addAll(getEligibleByRepasseAssessoria(threadContext.repasseAssessoriaId, remaining));
                remaining.removeAll(eligible);
                if (remaining.isEmpty()) return eligible;
            }

            if (!threadContext.hasArAccessPath && !threadContext.hasAbAccessPath) {
                return eligible;
            }

            // — Step 2: AR queue / AB access ──────────────────────────────────
            eligible.addAll(getEligibleByQueueAccess(threadContext, remaining));
            return eligible;
        }

        private Set<Id> getMentionedCommunicatorGroupIds(Id threadId) {
            return CommunicatorThreadService.getMentionedCommunicatorGroupIdsForThread(threadId);
        }

        private Set<Id> getEligibleByRepasseAssessoria(Id repasseAssessoriaId, Set<Id> platformUserIds) {
            Set<Id> eligible = new Set<Id>();
            if (repasseAssessoriaId == null || platformUserIds == null || platformUserIds.isEmpty()) return eligible;
            for (Id userId : platformUserIds) {
                Set<Id> assessoriaIds = getAssessoriaIdsForUser(userId);
                if (assessoriaIds.contains(repasseAssessoriaId)) {
                    eligible.add(userId);
                }
            }
            return eligible;
        }

        private Set<Id> getEligibleByQueueAccess(ThreadNotificationContext threadContext, Set<Id> platformUserIds) {
            Set<Id> eligible = new Set<Id>();
            if (threadContext == null) return eligible;

            if (threadContext.hasAbAccessPath == true) {
                eligible.addAll(platformUserIds);
                return eligible;
            }

            // AR queue rule: users whose role-queue group graph includes the AR owner queue
            if (threadContext.apuracaoRendaId == null) return eligible;

            Id arQueueId = arOwnerQueueByApuracaoIdCache.get(threadContext.apuracaoRendaId);
            if (!arOwnerQueueByApuracaoIdCache.containsKey(threadContext.apuracaoRendaId)) {
                List<AnaliseFinanceira__c> ars = [
                    SELECT OwnerId FROM AnaliseFinanceira__c WHERE Id = :threadContext.apuracaoRendaId LIMIT 1
                ];
                arQueueId = ars.isEmpty() ? null : ars[0].OwnerId;
                arOwnerQueueByApuracaoIdCache.put(threadContext.apuracaoRendaId, arQueueId);
            }
            if (arQueueId == null) return eligible;
            if (Test.isRunningTest() && testAnaliseFinanceiraOwnerQueueIdsByAnaliseId != null) {
                Id overriddenQueueId = testAnaliseFinanceiraOwnerQueueIdsByAnaliseId.get(threadContext.apuracaoRendaId);
                if (overriddenQueueId != null) {
                    arQueueId = overriddenQueueId;
                }
            }

            if (arQueueEligibleUsersByRootQueueIdCache.containsKey(arQueueId)) {
                Set<Id> preloadedEligible = new Set<Id>(arQueueEligibleUsersByRootQueueIdCache.get(arQueueId));
                preloadedEligible.retainAll(platformUserIds);
                return preloadedEligible;
            }

            Set<Id> queueAndSubGroups = getQueueHierarchyForRootQueue(arQueueId);

            // Direct GroupMember membership (user explicitly in the queue or a sub-group)
            for (GroupMember gm : [
                SELECT UserOrGroupId FROM GroupMember
                WHERE  GroupId IN :queueAndSubGroups
                AND    UserOrGroupId IN :platformUserIds
            ]) {
                eligible.add(gm.UserOrGroupId);
            }

            // Role-based membership: Salesforce does not create explicit GroupMember records
            // for users within role groups — the link is maintained implicitly via UserRoleId.
            // Example chain: Queue → PublicGroup → RoleGroup → User (via UserRoleId).
            // We resolve this by fetching the UserRole IDs associated with the traversed role
            // groups, then finding platform users who have one of those roles.
            Set<Id> relatedRoleIds = new Set<Id>();
            for (Group rg : [
                SELECT RelatedId
                FROM   Group
                WHERE  Id IN :queueAndSubGroups
                AND    Type = 'Role'
                AND    RelatedId != null
            ]) {
                relatedRoleIds.add(rg.RelatedId);
            }
            if (!relatedRoleIds.isEmpty()) {
                for (User u : [
                    SELECT Id FROM User
                    WHERE  Id IN :platformUserIds
                    AND    UserRoleId IN :relatedRoleIds
                ]) {
                    eligible.add(u.Id);
                }
            }

            return eligible;
        }
    }

    private static ThreadNotificationContext getThreadNotificationContext(Id threadId) {
        if (notificationContextByThreadIdCache.containsKey(threadId)) {
            return notificationContextByThreadIdCache.get(threadId);
        }
        CommunicatorThread__c thread = getNotificationThreadById(threadId);
        if (thread == null || String.isBlank(thread.RecordId__c)) {
            notificationContextByThreadIdCache.put(threadId, null);
            return null;
        }

        Id opportunityId = resolveOpportunityIdForNotification(thread.RecordId__c, thread.RecordType__c);
        if (opportunityId == null) {
            notificationContextByThreadIdCache.put(threadId, null);
            return null;
        }

        OpportunityNotificationContext opportunityContext = getOpportunityNotificationContext(opportunityId);
        ThreadNotificationContext threadContext = buildThreadNotificationContext(thread, opportunityId, opportunityContext);
        notificationContextByThreadIdCache.put(threadId, threadContext);
        return threadContext;
    }

    private static ThreadNotificationContext buildThreadNotificationContext(
        CommunicatorThread__c thread,
        Id opportunityId,
        OpportunityNotificationContext opportunityContext
    ) {
        if (thread == null || opportunityId == null || opportunityContext == null) return null;
        ThreadNotificationContext threadContext = new ThreadNotificationContext();
        threadContext.threadId = thread.Id;
        threadContext.opportunityId = opportunityId;
        threadContext.apuracaoRendaId = opportunityContext.apuracaoRendaId;
        threadContext.analiseCreditoId = opportunityContext.analiseCreditoId;
        threadContext.hasAbAccessPath = opportunityContext.hasAprovacaoBancaria == true;
        threadContext.hasArAccessPath = opportunityContext.apuracaoRendaId != null;
        threadContext.isRepasseContext = isRepasseNotificationContext(thread);
        if (threadContext.isRepasseContext) {
            Repasse__c repasse = getRepasseForNotification(thread, opportunityId);
            threadContext.repasseAssessoriaId = repasse != null ? repasse.ContaAssessoria__c : null;
        }
        return threadContext;
    }

    private static void preloadBulkNotificationAccessData(Set<Id> threadIds, Set<Id> candidateUserIds) {
        Set<Id> repasseIds = new Set<Id>();
        Set<Id> opportunityIds = new Set<Id>();
        Map<Id, Id> opportunityIdByThreadId = new Map<Id, Id>();
        Map<Id, Id> repasseIdByThreadId = new Map<Id, Id>();
        Set<Id> apuracaoIds = new Set<Id>();
        Set<Id> analiseCreditoIds = new Set<Id>();

        for (Id threadId : threadIds) {
            CommunicatorThread__c thread = notificationThreadByIdCache.get(threadId);
            if (thread == null || String.isBlank(thread.RecordId__c)) continue;
            try {
                Id recordId = (Id) thread.RecordId__c;
                if (thread.RecordType__c == 'Repasse__c') repasseIds.add(recordId);
                else opportunityIdByThreadId.put(threadId, recordId);
            } catch (Exception ignored) {
                // Invalid legacy record references resolve to no notification access, as before.
            }
        }

        Map<Id, Repasse__c> repassesById = CommunicatorRepasseService.getRepassesByIds(repasseIds);
        for (Id repasseId : repasseIds) notificationRepasseByIdCache.put(repasseId, repassesById.get(repasseId));
        for (Id threadId : threadIds) {
            CommunicatorThread__c thread = notificationThreadByIdCache.get(threadId);
            if (thread == null || thread.RecordType__c != 'Repasse__c' || String.isBlank(thread.RecordId__c)) continue;
            try {
                Id repasseId = (Id) thread.RecordId__c;
                repasseIdByThreadId.put(threadId, repasseId);
                Repasse__c repasse = repassesById.get(repasseId);
                if (repasse != null && repasse.Oportunidade__c != null) {
                    opportunityIdByThreadId.put(threadId, repasse.Oportunidade__c);
                }
            } catch (Exception ignored) {
                // Invalid legacy record references resolve to no notification access, as before.
            }
        }
        opportunityIds.addAll(opportunityIdByThreadId.values());

        Set<Id> missingOpportunityIds = new Set<Id>();
        for (Id opportunityId : opportunityIds) {
            if (!opportunityNotificationContextByOppId.containsKey(opportunityId)) missingOpportunityIds.add(opportunityId);
        }
        Map<Id, Opportunity> opportunitiesById = new Map<Id, Opportunity>();
        if (!missingOpportunityIds.isEmpty()) {
            opportunitiesById = new Map<Id, Opportunity>([
                SELECT Id, ApuracaoRenda__c, AnaliseCredito__c
                FROM Opportunity
                WHERE Id IN :missingOpportunityIds
            ]);
            for (Opportunity opportunity : opportunitiesById.values()) {
                if (opportunity.ApuracaoRenda__c != null) apuracaoIds.add(opportunity.ApuracaoRenda__c);
                if (opportunity.AnaliseCredito__c != null) analiseCreditoIds.add(opportunity.AnaliseCredito__c);
            }
        }

        for (Id opportunityId : opportunityIds) {
            OpportunityNotificationContext context = opportunityNotificationContextByOppId.get(opportunityId);
            if (context != null && context.analiseCreditoId != null) analiseCreditoIds.add(context.analiseCreditoId);
        }
        Set<Id> analisesWithAb = new Set<Id>();
        if (!analiseCreditoIds.isEmpty()) {
            for (AprovacaoBancaria__c approval : [
                SELECT AnaliseCredito__c
                FROM AprovacaoBancaria__c
                WHERE AnaliseCredito__c IN :analiseCreditoIds
            ]) {
                if (approval.AnaliseCredito__c != null) analisesWithAb.add(approval.AnaliseCredito__c);
            }
        }
        for (Opportunity opportunity : opportunitiesById.values()) {
            OpportunityNotificationContext context = new OpportunityNotificationContext();
            context.opportunityId = opportunity.Id;
            context.apuracaoRendaId = opportunity.ApuracaoRenda__c;
            context.analiseCreditoId = opportunity.AnaliseCredito__c;
            context.hasAprovacaoBancaria = analisesWithAb.contains(opportunity.AnaliseCredito__c);
            opportunityNotificationContextByOppId.put(opportunity.Id, context);
            if (opportunity.AnaliseCredito__c != null) {
                hasAprovacaoBancariaByAnaliseCreditoId.put(
                    opportunity.AnaliseCredito__c,
                    analisesWithAb.contains(opportunity.AnaliseCredito__c)
                );
            }
        }
        for (Id opportunityId : opportunityIds) {
            OpportunityNotificationContext context = opportunityNotificationContextByOppId.get(opportunityId);
            if (context == null) continue;
            if (context.apuracaoRendaId != null) apuracaoIds.add(context.apuracaoRendaId);
            if (context.analiseCreditoId != null) analiseCreditoIds.add(context.analiseCreditoId);
            context.hasAprovacaoBancaria = context.analiseCreditoId != null
                && analisesWithAb.contains(context.analiseCreditoId);
            if (context.analiseCreditoId != null) {
                hasAprovacaoBancariaByAnaliseCreditoId.put(context.analiseCreditoId, context.hasAprovacaoBancaria);
            }
        }

        Map<Id, Repasse__c> latestRepasseByOpportunity = new Map<Id, Repasse__c>();
        Set<Id> opportunityIdsNeedingLatestRepasse = new Set<Id>();
        for (Id threadId : threadIds) {
            CommunicatorThread__c thread = notificationThreadByIdCache.get(threadId);
            if (thread != null && thread.RecordType__c != 'Repasse__c' && isRepasseNotificationContext(thread)) {
                Id opportunityId = opportunityIdByThreadId.get(threadId);
                if (opportunityId != null && !repasseByOpportunityIdForNotificationCache.containsKey(opportunityId)) {
                    opportunityIdsNeedingLatestRepasse.add(opportunityId);
                }
            }
        }
        if (!opportunityIdsNeedingLatestRepasse.isEmpty()) {
            latestRepasseByOpportunity = CommunicatorRepasseService.getLatestRepassesByOpportunityIds(
                opportunityIdsNeedingLatestRepasse
            );
            for (Id opportunityId : opportunityIdsNeedingLatestRepasse) {
                repasseByOpportunityIdForNotificationCache.put(
                    opportunityId,
                    latestRepasseByOpportunity.containsKey(opportunityId)
                        ? latestRepasseByOpportunity.get(opportunityId)
                        : null
                );
            }
        }

        Map<Id, Repasse__c> repasseByThreadId = new Map<Id, Repasse__c>();
        for (Id threadId : repasseIdByThreadId.keySet()) {
            repasseByThreadId.put(threadId, repassesById.get(repasseIdByThreadId.get(threadId)));
        }
        for (Id threadId : threadIds) {
            CommunicatorThread__c thread = notificationThreadByIdCache.get(threadId);
            Id opportunityId = opportunityIdByThreadId.get(threadId);
            if (thread == null || opportunityId == null) {
                notificationContextByThreadIdCache.put(threadId, null);
                continue;
            }
            OpportunityNotificationContext opportunityContext = opportunityNotificationContextByOppId.get(opportunityId);
            ThreadNotificationContext context = buildThreadNotificationContext(thread, opportunityId, opportunityContext);
            if (thread.RecordType__c == 'Repasse__c' && context != null) {
                Repasse__c repasse = repasseByThreadId.get(threadId);
                context.repasseAssessoriaId = repasse == null ? null : repasse.ContaAssessoria__c;
            }
            notificationContextByThreadIdCache.put(threadId, context);
        }

        for (Id apuracaoId : apuracaoIds) {
            if (arOwnerQueueByApuracaoIdCache.containsKey(apuracaoId)) continue;
            arOwnerQueueByApuracaoIdCache.put(apuracaoId, null);
        }
        if (!apuracaoIds.isEmpty()) {
            for (AnaliseFinanceira__c analysis : [
                SELECT Id, OwnerId
                FROM AnaliseFinanceira__c
                WHERE Id IN :apuracaoIds
            ]) {
                arOwnerQueueByApuracaoIdCache.put(analysis.Id, analysis.OwnerId);
            }
        }
        if (Test.isRunningTest() && testAnaliseFinanceiraOwnerQueueIdsByAnaliseId != null) {
            for (Id apuracaoId : testAnaliseFinanceiraOwnerQueueIdsByAnaliseId.keySet()) {
                if (apuracaoIds.contains(apuracaoId)) {
                    arOwnerQueueByApuracaoIdCache.put(apuracaoId, testAnaliseFinanceiraOwnerQueueIdsByAnaliseId.get(apuracaoId));
                }
            }
        }

        Boolean needsRepasseAssessoriaAccess = false;
        for (ThreadNotificationContext context : notificationContextByThreadIdCache.values()) {
            if (context != null && context.isRepasseContext && context.repasseAssessoriaId != null) {
                needsRepasseAssessoriaAccess = true;
                break;
            }
        }
        if (needsRepasseAssessoriaAccess) preloadUserAssessoriaAccess(candidateUserIds);
        if (!apuracaoIds.isEmpty()) preloadArQueueAccess(apuracaoIds, candidateUserIds);
    }

    private static void preloadUserAssessoriaAccess(Set<Id> userIds) {
        Set<Id> missingUserIds = new Set<Id>();
        for (Id userId : userIds) {
            if (!queueIdsByUserIdCache.containsKey(userId) || !assessoriaIdsByUserIdCache.containsKey(userId)) {
                missingUserIds.add(userId);
            }
        }
        if (missingUserIds.isEmpty()) return;

        Map<Id, Id> roleIdByUserId = new Map<Id, Id>();
        for (User userRecord : [SELECT Id, UserRoleId FROM User WHERE Id IN :missingUserIds]) {
            roleIdByUserId.put(userRecord.Id, userRecord.UserRoleId);
            userRoleIdByUserIdCache.put(userRecord.Id, userRecord.UserRoleId);
        }
        for (Id userId : missingUserIds) {
            if (!userRoleIdByUserIdCache.containsKey(userId)) userRoleIdByUserIdCache.put(userId, null);
        }

        Set<Id> roleIds = new Set<Id>();
        for (Id roleId : roleIdByUserId.values()) if (roleId != null) roleIds.add(roleId);
        Map<Id, Set<Id>> roleGroupIdsByRole = new Map<Id, Set<Id>>();
        if (!roleIds.isEmpty()) {
            for (Group roleGroup : [
                SELECT Id, RelatedId
                FROM Group
                WHERE Type = 'Role'
                AND RelatedId IN :roleIds
            ]) {
                if (!roleGroupIdsByRole.containsKey(roleGroup.RelatedId)) {
                    roleGroupIdsByRole.put(roleGroup.RelatedId, new Set<Id>());
                }
                roleGroupIdsByRole.get(roleGroup.RelatedId).add(roleGroup.Id);
            }
        }

        Map<Id, Set<Id>> usersByFrontierId = new Map<Id, Set<Id>>();
        for (Id userId : missingUserIds) {
            if (!usersByFrontierId.containsKey(userId)) usersByFrontierId.put(userId, new Set<Id>());
            usersByFrontierId.get(userId).add(userId);
            Id roleId = roleIdByUserId.get(userId);
            if (roleId != null && roleGroupIdsByRole.containsKey(roleId)) {
                for (Id roleGroupId : roleGroupIdsByRole.get(roleId)) {
                    if (!usersByFrontierId.containsKey(roleGroupId)) usersByFrontierId.put(roleGroupId, new Set<Id>());
                    usersByFrontierId.get(roleGroupId).add(userId);
                }
            }
        }
        Map<Id, Set<Id>> queueIdsByUser = new Map<Id, Set<Id>>();
        Map<Id, Set<Id>> visitedUsersByGroupId = new Map<Id, Set<Id>>();
        for (Id userId : missingUserIds) {
            Id roleId = roleIdByUserId.get(userId);
            if (roleId == null || !roleGroupIdsByRole.containsKey(roleId)) continue;
            for (Id roleGroupId : roleGroupIdsByRole.get(roleId)) {
                if (!visitedUsersByGroupId.containsKey(roleGroupId)) visitedUsersByGroupId.put(roleGroupId, new Set<Id>());
                visitedUsersByGroupId.get(roleGroupId).add(userId);
            }
        }
        Set<Id> frontierIds = new Set<Id>(usersByFrontierId.keySet());
        for (Integer depth = 0; depth < 10 && !frontierIds.isEmpty(); depth++) {
            Map<Id, Set<Id>> usersByNextFrontier = new Map<Id, Set<Id>>();
            for (GroupMember membership : [
                SELECT GroupId, UserOrGroupId, Group.Type
                FROM GroupMember
                WHERE UserOrGroupId IN :frontierIds
            ]) {
                if (membership.GroupId == null || membership.UserOrGroupId == null) continue;
                Set<Id> owners = usersByFrontierId.get(membership.UserOrGroupId);
                if (owners == null || owners.isEmpty()) continue;
                if (membership.Group != null && membership.Group.Type == 'Queue') {
                    for (Id userId : owners) {
                        if (!queueIdsByUser.containsKey(userId)) queueIdsByUser.put(userId, new Set<Id>());
                        queueIdsByUser.get(userId).add(membership.GroupId);
                    }
                } else {
                        Set<Id> newOwners = trackNewGroupOwners(membership.GroupId, owners, visitedUsersByGroupId);
                    if (!newOwners.isEmpty()) {
                        if (!usersByNextFrontier.containsKey(membership.GroupId)) {
                            usersByNextFrontier.put(membership.GroupId, new Set<Id>());
                        }
                        usersByNextFrontier.get(membership.GroupId).addAll(newOwners);
                    }
                }
            }
            usersByFrontierId = usersByNextFrontier;
            frontierIds = new Set<Id>(usersByFrontierId.keySet());
        }

        Set<Id> allQueueIds = new Set<Id>();
        for (Id userId : missingUserIds) {
            if (!queueIdsByUser.containsKey(userId)) queueIdsByUser.put(userId, new Set<Id>());
            queueIdsByUserIdCache.put(userId, queueIdsByUser.get(userId));
            allQueueIds.addAll(queueIdsByUser.get(userId));
        }
        Map<Id, Set<Id>> assessoriaIdsByQueueId = new Map<Id, Set<Id>>();
        if (!allQueueIds.isEmpty()) {
            for (Account assessoria : [
                SELECT Id, IdFila__c
                FROM Account
                WHERE RecordType.DeveloperName = 'AssessoriaCredito'
                AND Status__c = 'Ativo'
                AND IdFila__c IN :allQueueIds
            ]) {
                if (assessoria.IdFila__c == null) continue;
                if (!assessoriaIdsByQueueId.containsKey(assessoria.IdFila__c)) {
                    assessoriaIdsByQueueId.put(assessoria.IdFila__c, new Set<Id>());
                }
                assessoriaIdsByQueueId.get(assessoria.IdFila__c).add(assessoria.Id);
            }
        }
        for (Id userId : missingUserIds) {
            Set<Id> assessoriaIds = new Set<Id>();
            for (Id queueId : queueIdsByUser.get(userId)) {
                if (assessoriaIdsByQueueId.containsKey(queueId)) {
                    assessoriaIds.addAll(assessoriaIdsByQueueId.get(queueId));
                }
            }
            assessoriaIdsByUserIdCache.put(userId, assessoriaIds);
        }
        for (Id roleId : roleIds) {
            roleGroupIdsByRoleIdCache.put(
                roleId,
                roleGroupIdsByRole.containsKey(roleId) ? roleGroupIdsByRole.get(roleId) : new Set<Id>()
            );
        }
    }

    @TestVisible
    private static Set<Id> trackNewGroupOwners(
        Id groupId,
        Set<Id> owners,
        Map<Id, Set<Id>> visitedUsersByGroupId
    ) {
        if (groupId == null || owners == null || owners.isEmpty()) return new Set<Id>();
        if (!visitedUsersByGroupId.containsKey(groupId)) visitedUsersByGroupId.put(groupId, new Set<Id>());
        Set<Id> visitedUsers = visitedUsersByGroupId.get(groupId);
        Set<Id> newOwners = new Set<Id>(owners);
        newOwners.removeAll(visitedUsers);
        visitedUsers.addAll(newOwners);
        return newOwners;
    }

    private static void preloadArQueueAccess(Set<Id> apuracaoIds, Set<Id> candidateUserIds) {
        Set<Id> rootQueueIds = new Set<Id>();
        for (Id apuracaoId : apuracaoIds) {
            Id queueId = arOwnerQueueByApuracaoIdCache.get(apuracaoId);
            if (queueId != null) rootQueueIds.add(queueId);
        }
        if (rootQueueIds.isEmpty()) return;

        Map<Id, Set<Id>> groupsByRoot = new Map<Id, Set<Id>>();
        Map<Id, Set<Id>> rootsByFrontierGroup = new Map<Id, Set<Id>>();
        for (Id rootId : rootQueueIds) {
            groupsByRoot.put(rootId, new Set<Id>{ rootId });
            rootsByFrontierGroup.put(rootId, new Set<Id>{ rootId });
        }
        Set<Id> frontier = new Set<Id>(rootQueueIds);
        for (Integer depth = 0; depth < 5 && !frontier.isEmpty(); depth++) {
            Map<Id, Set<Id>> rootsByNextGroup = new Map<Id, Set<Id>>();
            for (GroupMember membership : [
                SELECT GroupId, UserOrGroupId
                FROM GroupMember
                WHERE GroupId IN :frontier
            ]) {
                if (membership.UserOrGroupId == null || String.valueOf(membership.UserOrGroupId).left(3) != '00G') continue;
                Set<Id> parentRoots = rootsByFrontierGroup.get(membership.GroupId);
                if (parentRoots == null) continue;
                for (Id rootId : parentRoots) {
                    if (groupsByRoot.get(rootId).contains(membership.UserOrGroupId)) continue;
                    groupsByRoot.get(rootId).add(membership.UserOrGroupId);
                    if (!rootsByNextGroup.containsKey(membership.UserOrGroupId)) {
                        rootsByNextGroup.put(membership.UserOrGroupId, new Set<Id>());
                    }
                    rootsByNextGroup.get(membership.UserOrGroupId).add(rootId);
                }
            }
            rootsByFrontierGroup = rootsByNextGroup;
            frontier = new Set<Id>(rootsByFrontierGroup.keySet());
        }

        Set<Id> allGroupIds = new Set<Id>();
        Map<Id, Set<Id>> rootsByGroupId = new Map<Id, Set<Id>>();
        for (Id rootId : groupsByRoot.keySet()) {
            for (Id groupId : groupsByRoot.get(rootId)) {
                allGroupIds.add(groupId);
                if (!rootsByGroupId.containsKey(groupId)) rootsByGroupId.put(groupId, new Set<Id>());
                rootsByGroupId.get(groupId).add(rootId);
            }
            queueHierarchyByRootQueueIdCache.put(rootId, groupsByRoot.get(rootId));
        }

        Map<Id, Set<Id>> eligibleUsersByRoot = new Map<Id, Set<Id>>();
        for (Id rootId : rootQueueIds) eligibleUsersByRoot.put(rootId, new Set<Id>());
        if (!allGroupIds.isEmpty() && !candidateUserIds.isEmpty()) {
            for (GroupMember membership : [
                SELECT GroupId, UserOrGroupId
                FROM GroupMember
                WHERE GroupId IN :allGroupIds
                AND UserOrGroupId IN :candidateUserIds
            ]) {
                Set<Id> roots = rootsByGroupId.get(membership.GroupId);
                if (roots != null) for (Id rootId : roots) eligibleUsersByRoot.get(rootId).add(membership.UserOrGroupId);
            }

            Set<Id> relatedRoleIds = new Set<Id>();
            Map<Id, Set<Id>> rootsByRoleId = new Map<Id, Set<Id>>();
            for (Group roleGroup : [
                SELECT RelatedId
                FROM Group
                WHERE Id IN :allGroupIds
                AND Type = 'Role'
                AND RelatedId != null
            ]) {
                relatedRoleIds.add(roleGroup.RelatedId);
                if (!rootsByRoleId.containsKey(roleGroup.RelatedId)) rootsByRoleId.put(roleGroup.RelatedId, new Set<Id>());
                rootsByRoleId.get(roleGroup.RelatedId).addAll(rootsByGroupId.get(roleGroup.Id));
            }
            if (!relatedRoleIds.isEmpty()) {
                for (User userRecord : [
                    SELECT Id, UserRoleId
                    FROM User
                    WHERE Id IN :candidateUserIds
                    AND UserRoleId IN :relatedRoleIds
                ]) {
                    for (Id rootId : rootsByRoleId.get(userRecord.UserRoleId)) {
                        eligibleUsersByRoot.get(rootId).add(userRecord.Id);
                    }
                }
            }
        }
        for (Id rootId : rootQueueIds) {
            arQueueEligibleUsersByRootQueueIdCache.put(rootId, eligibleUsersByRoot.get(rootId));
        }
    }

    private static CommunicatorThread__c getNotificationThreadById(Id threadId) {
        if (threadId == null) return null;
        if (!notificationThreadByIdCache.containsKey(threadId)) {
            List<CommunicatorThread__c> threads = [
                SELECT Id, RecordId__c, RecordType__c, Stage__c
                FROM CommunicatorThread__c
                WHERE Id = :threadId
                LIMIT 1
            ];
            notificationThreadByIdCache.put(threadId, threads.isEmpty() ? null : threads[0]);
        }
        return notificationThreadByIdCache.get(threadId);
    }

    private static OpportunityNotificationContext getOpportunityNotificationContext(Id opportunityId) {
        if (opportunityId == null) return null;
        if (!opportunityNotificationContextByOppId.containsKey(opportunityId)) {
            OpportunityNotificationContext notificationContext;
            List<Opportunity> opportunityRows = [
                SELECT ApuracaoRenda__c, AnaliseCredito__c
                FROM Opportunity
                WHERE Id = :opportunityId
                LIMIT 1
            ];
            if (!opportunityRows.isEmpty()) {
                notificationContext = new OpportunityNotificationContext();
                notificationContext.opportunityId = opportunityId;
                notificationContext.apuracaoRendaId = opportunityRows[0].ApuracaoRenda__c;
                notificationContext.analiseCreditoId = opportunityRows[0].AnaliseCredito__c;
                notificationContext.hasAprovacaoBancaria = hasAprovacaoBancaria(opportunityRows[0].AnaliseCredito__c);
            }
            opportunityNotificationContextByOppId.put(opportunityId, notificationContext);
        }
        return opportunityNotificationContextByOppId.get(opportunityId);
    }

    private static Boolean hasAprovacaoBancaria(Id analiseCreditoId) {
        if (analiseCreditoId == null) return false;
        if (!hasAprovacaoBancariaByAnaliseCreditoId.containsKey(analiseCreditoId)) {
            Integer abCount = [
                SELECT COUNT()
                FROM AprovacaoBancaria__c
                WHERE AnaliseCredito__c = :analiseCreditoId
            ];
            hasAprovacaoBancariaByAnaliseCreditoId.put(analiseCreditoId, abCount > 0);
        }
        return hasAprovacaoBancariaByAnaliseCreditoId.get(analiseCreditoId) == true;
    }

    private static Repasse__c getRepasseForNotification(CommunicatorThread__c thread, Id opportunityId) {
        if (thread == null) return null;
        if (thread.RecordType__c == 'Repasse__c') {
            Id repasseId = (Id) thread.RecordId__c;
            if (!notificationRepasseByIdCache.containsKey(repasseId)) {
                Map<Id, Repasse__c> repassesById = CommunicatorRepasseService.getRepassesByIds(new Set<Id>{ repasseId });
                notificationRepasseByIdCache.put(repasseId, repassesById.get(repasseId));
            }
            return notificationRepasseByIdCache.get(repasseId);
        }
        if (opportunityId == null) return null;
        if (!repasseByOpportunityIdForNotificationCache.containsKey(opportunityId)) {
            Map<Id, Repasse__c> repasseByOpportunityId =
                CommunicatorRepasseService.getLatestRepassesByOpportunityIds(new Set<Id>{ opportunityId });
            repasseByOpportunityIdForNotificationCache.put(
                opportunityId,
                repasseByOpportunityId.containsKey(opportunityId) ? repasseByOpportunityId.get(opportunityId) : null
            );
        }
        return repasseByOpportunityIdForNotificationCache.get(opportunityId);
    }

    private static Boolean isRepasseNotificationContext(CommunicatorThread__c thread) {
        if (thread == null) return false;
        if (thread.RecordType__c == 'Repasse__c') return true;
        return isRepasseMacroPhase(thread.Stage__c);
    }

    private static Boolean isRepasseMacroPhase(String stageName) {
        String normalizedStage = normalizeCommunicatorStage(stageName);
        return new Set<String>{
            'aguardando inicio', 'formulario', 'conferencia de dossie',
            'pendencias', 'assinatura do repasse', 'retencao', 'triagem', 'outros'
        }.contains(normalizedStage);
    }

    private static Set<Id> getMentionedCommunicatorGroupIdsForThread(Id threadId) {
        if (threadId == null) return new Set<Id>();
        if (!mentionedGroupIdsByThreadIdCache.containsKey(threadId)) {
            Set<Id> groupIds = new Set<Id>();
            for (CommunicatorMessage__c msg : [
                SELECT MentionedGroupIds__c
                FROM CommunicatorMessage__c
                WHERE Thread__c = :threadId
                AND HasMention__c = true
                LIMIT 500
            ]) {
                if (String.isBlank(msg.MentionedGroupIds__c)) continue;
                groupIds.addAll(CommunicatorMentionService.deserializeUserIds(msg.MentionedGroupIds__c));
            }
            mentionedGroupIdsByThreadIdCache.put(threadId, groupIds);
        }
        return new Set<Id>(mentionedGroupIdsByThreadIdCache.get(threadId));
    }

    private static Set<Id> getQueueHierarchyForRootQueue(Id rootQueueId) {
        if (rootQueueId == null) return new Set<Id>();
        if (!queueHierarchyByRootQueueIdCache.containsKey(rootQueueId)) {
            Set<Id> queueAndSubGroups = new Set<Id>{ rootQueueId };
            Set<Id> frontier = new Set<Id>{ rootQueueId };
            Integer depth = 0;
            while (!frontier.isEmpty() && depth < 5) {
                depth++;
                Set<Id> next = new Set<Id>();
                for (GroupMember gm : [
                    SELECT UserOrGroupId
                    FROM GroupMember
                    WHERE GroupId IN :frontier
                ]) {
                    if (gm.UserOrGroupId == null) continue;
                    String idPrefix = String.valueOf(gm.UserOrGroupId).left(3);
                    if (idPrefix == '00G' && !queueAndSubGroups.contains(gm.UserOrGroupId)) {
                        queueAndSubGroups.add(gm.UserOrGroupId);
                        next.add(gm.UserOrGroupId);
                    }
                }
                frontier = next;
            }
            queueHierarchyByRootQueueIdCache.put(rootQueueId, queueAndSubGroups);
        }
        return new Set<Id>(queueHierarchyByRootQueueIdCache.get(rootQueueId));
    }

    private static Set<Id> getAssessoriaIdsForUser(Id userId) {
        if (userId == null) return new Set<Id>();
        if (!assessoriaIdsByUserIdCache.containsKey(userId)) {
            Set<Id> queueIds = getQueueIdsForUser(userId);
            assessoriaIdsByUserIdCache.put(userId, CommunicatorRepasseService.getAssessoriaIdsByQueueIds(queueIds));
        }
        return new Set<Id>(assessoriaIdsByUserIdCache.get(userId));
    }

    private static Set<Id> getQueueIdsForUser(Id userId) {
        if (userId == null) return new Set<Id>();
        if (!queueIdsByUserIdCache.containsKey(userId)) {
            Set<Id> queueIds = new Set<Id>();
            Set<Id> visitedGroupIds = new Set<Id>();
            Set<Id> frontierIds = new Set<Id>{ userId };
            Id userRoleId = getUserRoleIdForUser(userId);
            if (userRoleId != null) {
                frontierIds.addAll(getRoleGroupIdsForRole(userRoleId));
            }

            Integer safetyDepth = 0;
            while (!frontierIds.isEmpty() && safetyDepth < 10) {
                safetyDepth++;
                Set<Id> nextFrontier = new Set<Id>();
                Map<Id, List<GroupMember>> membershipsByMemberId = getParentGroupMemberships(frontierIds);
                for (Id frontierId : frontierIds) {
                    List<GroupMember> memberships = membershipsByMemberId.get(frontierId);
                    if (memberships == null) continue;
                    for (GroupMember gm : memberships) {
                        if (gm.GroupId == null || visitedGroupIds.contains(gm.GroupId)) continue;
                        visitedGroupIds.add(gm.GroupId);
                        if (gm.Group != null && gm.Group.Type == 'Queue') {
                            queueIds.add(gm.GroupId);
                        } else {
                            nextFrontier.add(gm.GroupId);
                        }
                    }
                }
                frontierIds = nextFrontier;
            }
            queueIdsByUserIdCache.put(userId, queueIds);
        }
        return new Set<Id>(queueIdsByUserIdCache.get(userId));
    }

    private static Id getUserRoleIdForUser(Id userId) {
        if (userId == null) return null;
        if (!userRoleIdByUserIdCache.containsKey(userId)) {
            for (User userRecord : [
                SELECT UserRoleId
                FROM User
                WHERE Id = :userId
                LIMIT 1
            ]) {
                userRoleIdByUserIdCache.put(userId, userRecord.UserRoleId);
            }
            if (!userRoleIdByUserIdCache.containsKey(userId)) {
                userRoleIdByUserIdCache.put(userId, null);
            }
        }
        return userRoleIdByUserIdCache.get(userId);
    }

    private static Set<Id> getRoleGroupIdsForRole(Id userRoleId) {
        if (userRoleId == null) return new Set<Id>();
        if (!roleGroupIdsByRoleIdCache.containsKey(userRoleId)) {
            Set<Id> roleGroupIds = new Set<Id>();
            for (Group roleGroup : [
                SELECT Id
                FROM Group
                WHERE Type = 'Role'
                AND RelatedId = :userRoleId
            ]) {
                roleGroupIds.add(roleGroup.Id);
            }
            roleGroupIdsByRoleIdCache.put(userRoleId, roleGroupIds);
        }
        return new Set<Id>(roleGroupIdsByRoleIdCache.get(userRoleId));
    }

    private static Map<Id, List<GroupMember>> getParentGroupMemberships(Set<Id> memberIds) {
        Set<Id> missingMemberIds = new Set<Id>();
        for (Id memberId : memberIds) {
            if (memberId != null && !parentGroupMembershipsByMemberIdCache.containsKey(memberId)) {
                missingMemberIds.add(memberId);
            }
        }
        if (!missingMemberIds.isEmpty()) {
            Map<Id, List<GroupMember>> fetchedMemberships = new Map<Id, List<GroupMember>>();
            for (GroupMember membership : [
                SELECT GroupId, UserOrGroupId, Group.Type
                FROM GroupMember
                WHERE UserOrGroupId IN :missingMemberIds
            ]) {
                if (!fetchedMemberships.containsKey(membership.UserOrGroupId)) {
                    fetchedMemberships.put(membership.UserOrGroupId, new List<GroupMember>());
                }
                fetchedMemberships.get(membership.UserOrGroupId).add(membership);
            }
            for (Id missingMemberId : missingMemberIds) {
                parentGroupMembershipsByMemberIdCache.put(
                    missingMemberId,
                    fetchedMemberships.containsKey(missingMemberId)
                        ? fetchedMemberships.get(missingMemberId)
                        : new List<GroupMember>()
                );
            }
        }

        Map<Id, List<GroupMember>> membershipsByMemberId = new Map<Id, List<GroupMember>>();
        for (Id memberId : memberIds) {
            if (memberId != null && parentGroupMembershipsByMemberIdCache.containsKey(memberId)) {
                membershipsByMemberId.put(memberId, parentGroupMembershipsByMemberIdCache.get(memberId));
            }
        }
        return membershipsByMemberId;
    }

    private static Id resolveOpportunityIdForNotification(String recordId, String recordType) {
        if (String.isBlank(recordId)) return null;
        try {
            if (recordType == 'Opportunity' || String.isBlank(recordType)) {
                return (Id) recordId;
            }
            if (recordType == 'Repasse__c') {
                Map<Id, Repasse__c> repassesById = CommunicatorRepasseService.getRepassesByIds(
                    new Set<Id>{ (Id) recordId }
                );
                Repasse__c repasse = repassesById.get((Id) recordId);
                return repasse != null ? repasse.Oportunidade__c : null;
            }
        } catch (Exception e) {
            return null;
        }
        return null;
    }
    public static CommunicatorThread__c getOrCreateGroupThread(Id groupId) {
        List<CommunicatorThread__c> existing = [
            SELECT Id, Name, RecordId__c, RecordType__c, Status__c, Stage__c,
                   LastMessageAt__c, UnreadCount__c
            FROM   CommunicatorThread__c
            WHERE  RecordId__c    = :String.valueOf(groupId)
            AND    RecordType__c  = 'CommunicatorGroup__c'
            AND    Status__c      = 'Active'
            LIMIT  1
        ];
        if (!existing.isEmpty()) return existing[0];

        CommunicatorThread__c newThread = new CommunicatorThread__c(
            RecordId__c   = String.valueOf(groupId),
            RecordType__c = 'CommunicatorGroup__c',
            Stage__c      = 'group',
            Status__c     = 'Active'
        );
        insert newThread;
        return newThread;
    }
    // Usuarios de comunidade nao tem sharing access a CommunicatorThread__c e CommunicatorMessage__c.
    // Leituras sao restritas aos IDs validados via participant ownership.
    private without sharing class CommunityThreadBypassReader {
        List<CommunicatorThread__c> getThreadsByRecordId(String recordId) {
            if (String.isBlank(recordId)) return new List<CommunicatorThread__c>();
            return [
                SELECT Id, Name, RecordId__c, RecordType__c, Stage__c, LastMessageAt__c
                FROM   CommunicatorThread__c
                WHERE  RecordId__c = :recordId
                AND    Status__c  != 'Archived'
                ORDER  BY LastMessageAt__c ASC NULLS LAST
            ];
        }
        List<CommunicatorThread__c> getThreadsByIds(Set<Id> threadIds, String recordId) {
            if (threadIds == null || threadIds.isEmpty()) return new List<CommunicatorThread__c>();
            return [
                SELECT Id, Name, RecordId__c, RecordType__c, Stage__c, LastMessageAt__c
                FROM   CommunicatorThread__c
                WHERE  Id IN :threadIds
                AND    RecordId__c = :recordId
                AND    Status__c  != 'Archived'
                ORDER  BY LastMessageAt__c ASC NULLS LAST
            ];
        }
        List<CommunicatorMessage__c> getLastMessagesByThreadIds(Set<Id> threadIds) {
            if (threadIds == null || threadIds.isEmpty()) return new List<CommunicatorMessage__c>();
            return [
                SELECT Thread__c, Body__c, SentAt__c, Sender__r.Name, Sender__r.SmallPhotoUrl, IsSystemMessage__c
                FROM   CommunicatorMessage__c
                WHERE  Thread__c IN :threadIds
                ORDER  BY SentAt__c DESC, Id DESC
            ];
        }
    }

    private class OpportunityNotificationContext {
        Id opportunityId;
        Id apuracaoRendaId;
        Id analiseCreditoId;
        Boolean hasAprovacaoBancaria;
    }

    private class ThreadNotificationContext {
        Id threadId;
        Id opportunityId;
        Id apuracaoRendaId;
        Id analiseCreditoId;
        Boolean hasArAccessPath;
        Boolean hasAbAccessPath;
        Boolean isRepasseContext;
        Id repasseAssessoriaId;
    }
}