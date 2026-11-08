/**
 * @description Controller layer for the Communicator Chat system.
 *              Exposes AuraEnabled methods consumed by LWC components.
 *              All business logic is delegated to service classes.
 *
 *              Thread is record-agnostic: any SObject Id can be used.
 */
public without sharing class CommunicatorChatController {
    @TestVisible private static Boolean forceSalesforcePlatformUserForTest;
    @TestVisible private static Boolean useSalesforcePlatformOverrideForTest;
    @TestVisible private static String forceUserLicenseNameForTest;
    @TestVisible private static Boolean useUserLicenseNameOverrideForTest;
    @TestVisible private static Boolean forceNoGroupCreatePermissionForTest = false;
    @TestVisible private static Boolean forceHasCommunicatorChatPermissionForTest = null;

    private static Boolean hasGroupCreatePermission() {
        if (Test.isRunningTest()) {
            return forceNoGroupCreatePermissionForTest != true;
        }
        return FeatureManagement.checkPermission('CommunicatorChatGroup');
    }

   
    // Thread
   

    /**
     * @description Returns or creates the thread for a given record Id.
     * @param recordId   Id of any SObject (Opportunity, Account, Case, etc.)
     * @param objectType API name of the SObject. Defaults to empty string if not provided.
     * @return CommunicatorThread__c record.
     */

    @AuraEnabled(cacheable=false)
    public static CommunicatorDTOs.ThreadListItemDTO getThreadDetail(Id threadId) {
        try {
            CommunicatorBroadcastService.assertConventionalThread(threadId);
            return CommunicatorThreadService.getThreadDetail(threadId);
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    @AuraEnabled(cacheable=false)
    public static List<CommunicatorDTOs.ThreadListItemDTO> getThreadsForRecord(String recordId) {
        try {
            if (CommunicatorBroadcastService.isBroadcastRecordId(recordId)) {
                return new List<CommunicatorDTOs.ThreadListItemDTO>();
            }
            return CommunicatorThreadService.getThreadsForRecord(recordId);
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    @AuraEnabled(cacheable=false)
    public static CommunicatorDTOs.NotificationNavigationDTO getNotificationNavigationContext(
        String threadId,
        String messageId,
        String targetRecordId
    ) {
        try {
            if (!hasCommunicatorChatPermission()) return new CommunicatorDTOs.NotificationNavigationDTO();
            return CommunicatorThreadService.getNotificationNavigationContext(threadId, messageId, targetRecordId);
        } catch (Exception ex) {
            return new CommunicatorDTOs.NotificationNavigationDTO();
        }
    }

    @AuraEnabled(cacheable=false)
    public static List<CommunicatorDTOs.ThreadListItemDTO> getThreadsForRecordPreview(String recordId) {
        try {
            if (CommunicatorBroadcastService.isBroadcastRecordId(recordId)) {
                return new List<CommunicatorDTOs.ThreadListItemDTO>();
            }
            return CommunicatorThreadService.getThreadsForRecordPreview(recordId);
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    @AuraEnabled(cacheable=false)
    public static Boolean canRestoreViewedThread(Id threadId, String expectedRecordId) {
        try {
            if (CommunicatorBroadcastService.isBroadcastThread(threadId)) return false;
            return CommunicatorThreadService.canCurrentUserRestoreViewedThread(threadId, expectedRecordId);
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    @AuraEnabled(cacheable=false)
    public static List<CommunicatorDTOs.ThreadListItemDTO> getThreadList(
        Integer pageSize, Integer offsetVal, String filter
    ) {
        try {
            return CommunicatorThreadService.getThreadList(pageSize, offsetVal, filter);
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    @AuraEnabled(cacheable=false)
    public static Integer getThreadCount(String filter) {
        try {
            return CommunicatorThreadService.getThreadCount(filter);
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    @AuraEnabled(cacheable=false)
    public static List<CommunicatorDTOs.ThreadListItemDTO> getOpportunityChatList(
        Integer pageSize, Integer offsetVal, String filter, String keyword
    ) {
        try {
            return CommunicatorThreadService.getOpportunityChatList(pageSize, offsetVal, filter, keyword);
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    @AuraEnabled(cacheable=false)
    public static Integer getOpportunityChatCount(String filter, String keyword) {
        try {
            return CommunicatorThreadService.getOpportunityChatCount(filter, keyword);
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    @AuraEnabled(cacheable=false)
    public static List<CommunicatorDTOs.ThreadPresenceOverrideDTO> getThreadPresenceOverrides(List<Id> threadIds) {
        try {
            return CommunicatorThreadService.getThreadPresenceOverrides(
                new List<Id>(CommunicatorBroadcastService.filterConventionalThreadIds(threadIds))
            );
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    @AuraEnabled(cacheable=false)
    public static CommunicatorThread__c getOrCreateThread(String recordId, String objectType) {
        try {
            if (CommunicatorBroadcastService.isBroadcastRecordId(recordId)) {
                throw new CommunicatorException('Use a API específica de comunicados.');
            }
            String objType = String.isBlank(objectType) ? '' : objectType;
            return CommunicatorThreadService.getOrCreateThread(recordId, objType);
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

   
    // Messages
   

    @AuraEnabled(cacheable=false)
    public static List<CommunicatorMessage__c> getMessages(Id threadId, Integer pageSize, Integer offsetVal) {
        try {
            CommunicatorBroadcastService.assertConventionalThread(threadId);
            return CommunicatorMessageService.getMessages(threadId, pageSize, offsetVal);
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    @AuraEnabled(cacheable=false)
    public static List<CommunicatorMessage__c> getMessagesAcrossThreads(
        List<Id> threadIds,
        Integer pageSize,
        Integer offsetVal
    ) {
        try {
            return CommunicatorMessageService.getMessagesAcrossThreads(
                new List<Id>(CommunicatorBroadcastService.filterConventionalThreadIds(threadIds)),
                pageSize,
                offsetVal
            );
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    @AuraEnabled(cacheable=false)
    public static Integer getMessageOffset(Id threadId, Id messageId) {
        try {
            CommunicatorBroadcastService.assertConventionalThread(threadId);
            return CommunicatorMessageService.getMessageOffset(threadId, messageId);
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    @AuraEnabled(cacheable=false)
    public static Integer getMessageOffsetAcrossThreads(List<Id> threadIds, Id messageId) {
        try {
            return CommunicatorMessageService.getMessageOffsetAcrossThreads(
                new List<Id>(CommunicatorBroadcastService.filterConventionalThreadIds(threadIds)),
                messageId
            );
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    @AuraEnabled(cacheable=false)
    public static CommunicatorMessage__c sendMessage(Id threadId, String messageBody, String mentionIds) {
        try {
            CommunicatorBroadcastService.assertConventionalThread(threadId);
            return CommunicatorMessageService.sendMessage(threadId, messageBody, mentionIds);
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    @AuraEnabled(cacheable=false)
    public static CommunicatorMessage__c sendMessageWithAttachment(Id threadId, String messageBody, Id contentDocumentId, String mentionIds) {
        try {
            CommunicatorBroadcastService.assertConventionalThread(threadId);
            CommunicatorBroadcastService.assertConventionalDocuments(new Set<Id>{ contentDocumentId });
            return CommunicatorMessageService.sendMessageWithAttachment(threadId, messageBody, contentDocumentId, mentionIds);
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    @AuraEnabled(cacheable=false)
    public static CommunicatorMessage__c sendMessageWithAttachments(
        Id threadId,
        String messageBody,
        List<Id> contentDocumentIds,
        String mentionIds
    ) {
        try {
            CommunicatorBroadcastService.assertConventionalThread(threadId);
            CommunicatorBroadcastService.assertConventionalDocuments(
                contentDocumentIds == null ? new Set<Id>() : new Set<Id>(contentDocumentIds)
            );
            return CommunicatorMessageService.sendMessageWithAttachments(
                threadId,
                messageBody,
                contentDocumentIds,
                mentionIds
            );
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    @AuraEnabled(cacheable=false)
    public static Id uploadAttachmentFromBase64(Id threadId, String fileName, String base64Data) {
        try {
            CommunicatorBroadcastService.assertConventionalThread(threadId);
            return CommunicatorMessageService.uploadAttachmentFromBase64(threadId, fileName, base64Data);
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    @AuraEnabled(cacheable=false)
    public static CommunicatorDTOs.SocketInboundResultDTO reconcileSocketMessage(
        Id threadId,
        String threadExternalId,
        String messageId,
        String messageBody,
        String userIdsJson,
        String senderExternalId
    ) {
        try {
            return CommunicatorMessageService.reconcileSocketInboundMessage(
                threadId,
                threadExternalId,
                messageId,
                messageBody,
                userIdsJson,
                senderExternalId
            );
        } catch (Exception ex) {
            CommunicatorDTOs.SocketInboundResultDTO result = new CommunicatorDTOs.SocketInboundResultDTO();
            result.success = false;
            result.created = false;
            result.status = 'ERROR';
            result.errorMessage = ex.getMessage();
            return result;
        }
    }

    @AuraEnabled(cacheable=false)
    public static Integer getMessageCount(Id threadId) {
        try {
            CommunicatorBroadcastService.assertConventionalThread(threadId);
            return CommunicatorMessageService.getMessageCount(threadId);
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    @AuraEnabled(cacheable=false)
    public static Integer getMessageCountAcrossThreads(List<Id> threadIds) {
        try {
            return CommunicatorMessageService.getMessageCountAcrossThreads(
                new List<Id>(CommunicatorBroadcastService.filterConventionalThreadIds(threadIds))
            );
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    @AuraEnabled(cacheable=false)
    public static List<Id> getThreadHistoryParticipantIds(Id threadId) {
        try {
            CommunicatorBroadcastService.assertConventionalThread(threadId);
            return CommunicatorMessageService.getThreadHistoryParticipantIds(threadId);
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    @AuraEnabled(cacheable=false)
    public static List<Id> getThreadHistoryParticipantIdsAcrossThreads(List<Id> threadIds) {
        try {
            return CommunicatorMessageService.getThreadHistoryParticipantIdsAcrossThreads(
                new List<Id>(CommunicatorBroadcastService.filterConventionalThreadIds(threadIds))
            );
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    @AuraEnabled(cacheable=false)
    public static Map<String, String> getAttachmentVersionIds(List<String> contentDocumentIds) {
        try {
            Set<Id> documentIds = new Set<Id>();
            for (String documentId : contentDocumentIds == null ? new List<String>() : contentDocumentIds) {
                if (String.isBlank(documentId)) continue;
                try { documentIds.add((Id) documentId); }
                catch (Exception ex) { }
            }
            documentIds.removeAll(CommunicatorBroadcastService.getBroadcastDocumentIds(documentIds));
            List<String> conventionalDocumentIds = new List<String>();
            for (Id documentId : documentIds) conventionalDocumentIds.add(String.valueOf(documentId));
            Map<String, String> versionIds = CommunicatorFileShareService.getLatestVersionIds(conventionalDocumentIds);
            CommunicatorFileShareService.repairNetworkAccess(conventionalDocumentIds);
            return versionIds;
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    @AuraEnabled(cacheable=false)
    public static CommunicatorDTOs.AttachmentFileDTO getAttachmentFile(
        String contentDocumentId,
        String contentVersionId,
        Id threadId,
        Id messageId,
        Id opportunityId
    ) {
        try {
            CommunicatorBroadcastService.assertConventionalAttachmentRequest(
                threadId, messageId, contentDocumentId, contentVersionId
            );
            return CommunicatorMessageService.getAttachmentFile(
                contentDocumentId,
                contentVersionId,
                threadId,
                messageId,
                opportunityId
            );
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    @AuraEnabled(cacheable=false)
    public static List<CommunicatorDTOs.MessageAttachmentDTO> getMessageAttachments(List<Id> messageIds) {
        try {
            Set<Id> conventionalMessageIds = new Set<Id>(messageIds == null ? new List<Id>() : messageIds);
            conventionalMessageIds.removeAll(
                CommunicatorBroadcastService.getBroadcastMessageIds(conventionalMessageIds)
            );
            return CommunicatorMessageService.getMessageAttachments(new List<Id>(conventionalMessageIds));
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    @AuraEnabled(cacheable=false)
    public static List<CommunicatorMessage__c> pollNewMessages(Id threadId, String lastTimestamp) {
        try {
            CommunicatorBroadcastService.assertConventionalThread(threadId);
            DateTime sinceDateTime = (DateTime) JSON.deserialize('"' + lastTimestamp + '"', DateTime.class);
            return CommunicatorMessageService.getMessagesSince(threadId, sinceDateTime);
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    @AuraEnabled(cacheable=false)
    public static List<CommunicatorMessage__c> pollNewMessagesAcrossThreads(List<Id> threadIds, String lastTimestamp) {
        try {
            DateTime sinceDateTime = (DateTime) JSON.deserialize('"' + lastTimestamp + '"', DateTime.class);
            return CommunicatorMessageService.getMessagesSinceAcrossThreads(
                new List<Id>(CommunicatorBroadcastService.filterConventionalThreadIds(threadIds)),
                sinceDateTime
            );
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    @AuraEnabled(cacheable=false)
    public static CommunicatorDTOs.MessagePollPageDTO pollTimeline(
        Id threadId,
        List<Id> threadIds,
        String cursor,
        Integer pageSize
    ) {
        try {
            if (threadId != null) CommunicatorBroadcastService.assertConventionalThread(threadId);
            List<Id> conventionalThreadIds = threadId == null
                ? new List<Id>(CommunicatorBroadcastService.filterConventionalThreadIds(threadIds))
                : new List<Id>{ threadId };
            Set<Id> visibleThreadIds = CommunicatorThreadService.getVisibleConventionalThreadIdsForCurrentUser(
                new Set<Id>(conventionalThreadIds)
            );
            if (threadId != null && !visibleThreadIds.contains(threadId)) {
                throw new CommunicatorException('Thread not found or not accessible.');
            }
            Set<Id> authorizedThreadIds = new Set<Id>(conventionalThreadIds);
            authorizedThreadIds.retainAll(visibleThreadIds);
            conventionalThreadIds = new List<Id>(authorizedThreadIds);
            return CommunicatorMessageService.pollTimeline(null, conventionalThreadIds, cursor, pageSize);
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

   
    // Search
   

    @AuraEnabled(cacheable=false)
    public static List<CommunicatorMessage__c> searchMessages(Id threadId, String keyword) {
        try {
            CommunicatorBroadcastService.assertConventionalThread(threadId);
            return CommunicatorSearchService.searchMessages(threadId, keyword);
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    @AuraEnabled(cacheable=false)
    public static List<CommunicatorMessage__c> searchMessagesAcrossThreads(List<Id> threadIds, String keyword) {
        try {
            return CommunicatorSearchService.searchMessagesAcrossThreads(
                new List<Id>(CommunicatorBroadcastService.filterConventionalThreadIds(threadIds)),
                keyword
            );
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

   
    // Notifications
   

    @AuraEnabled(cacheable=false)
    public static Integer getUnreadCount(Id threadId) {
        try {
            CommunicatorBroadcastService.assertConventionalThread(threadId);
            return CommunicatorNotificationService.getUnreadCount(threadId);
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    @AuraEnabled(cacheable=false)
    public static Integer getOpportunityUnreadMessageTotal(
        Integer pageSize,
        Integer offsetVal,
        String keyword
    ) {
        try {
            return CommunicatorNotificationService.getOpportunityUnreadMessageTotal(
                pageSize,
                offsetVal,
                keyword
            );
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    @AuraEnabled(cacheable=false)
    public static Integer getGlobalUnreadCount() {
        try {
            return CommunicatorNotificationRecordService.getGlobalUnreadNotificationCount();
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    @AuraEnabled(cacheable=false)
    public static void markThreadAsRead(Id threadId) {
        try {
            CommunicatorBroadcastService.assertConventionalThread(threadId);
            CommunicatorNotificationService.markThreadAsRead(threadId);
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    @AuraEnabled(cacheable=false)
    public static void markGroupMentionsAsRead(Id groupId) {
        try {
            CommunicatorBroadcastService.assertConventionalGroup(groupId);
            CommunicatorNotificationRecordService.markGroupMentionsAsRead(groupId);
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

   
    // Participants
   

    @AuraEnabled(cacheable=false)
    public static List<CommunicatorParticipant__c> getParticipants(Id threadId) {
        try {
            CommunicatorBroadcastService.assertConventionalThread(threadId);
            return CommunicatorParticipantService.getParticipants(threadId);
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

   
    // Record name (generic — any SObject)
   

    /**
     * @description Returns the Name field of any SObject record dynamically.
     *              Used by LWC pickers to display record names without
     *              hardcoding the object type.
     * @param recordId Id of any SObject with a Name field.
     * @return The Name field value.
     */
    @AuraEnabled(cacheable=true)
    public static String getRecordName(String recordId) {
        try {
            if (String.isBlank(recordId)) return '';

            Id sfId = (Id) recordId;
            Schema.SObjectType sObjectType = sfId.getSObjectType();
            String objectName = sObjectType.getDescribe().getName();

            if (objectName == 'Repasse__c') {
                Map<Id, Repasse__c> repassesById = CommunicatorRepasseService.getRepassesByIds(new Set<Id>{ sfId });
                Repasse__c repasse = repassesById.get(sfId);
                if (repasse == null || repasse.Oportunidade__c == null) return '';
                if (isCurrentUserSalesforcePlatform(getCurrentUserLicenseName())
                    && !CommunicatorThreadService.isRepasseVisibleForCurrentUser(repasse)) {
                    return '';
                }

                Set<Id> visibleOppIds = CommunicatorOpportunityAccessService.getVisibleOpportunityIds(
                    new Set<Id>{ repasse.Oportunidade__c }
                );
                return visibleOppIds.contains(repasse.Oportunidade__c) ? repasse.Name : '';
            }

            if (objectName == 'Opportunity' && isCurrentUserSalesforcePlatform(getCurrentUserLicenseName())) {
                Set<Id> visibleOppIds = CommunicatorOpportunityAccessService.getVisibleOpportunityIds(
                    new Set<Id>{ sfId }
                );
                if (!visibleOppIds.contains(sfId)) return '';
                String repassePhase = CommunicatorRepassePhaseHelper.getRepasseMacroPhaseByOppId(sfId);
                if (String.isNotBlank(repassePhase)) {
                    Map<Id, Repasse__c> repassesByOppId = CommunicatorThreadService.getVisibleLatestRepassesByOpportunityIds(
                        new Set<Id>{ sfId }
                    );
                    Repasse__c repasse = repassesByOppId.get(sfId);
                    if (repasse != null) {
                        return repasse.Name;
                    }
                }
            }

            List<SObject> records = Database.query(
                'SELECT Name FROM ' + objectName + ' WHERE Id = :sfId LIMIT 1'
            );
            return records.isEmpty() ? '' : (String) records[0].get('Name');
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    /**
     * @description Returns Opportunity.ApuracaoRenda__r.Name for the given Opportunity Ids.
     *              Used by LWC to enrich "recent opportunities" cards with AR label.
     * @param opportunityIds List of Opportunity Ids.
     * @return Map<OpportunityId, ApuracaoRendaName>.
     */
    @AuraEnabled(cacheable=true)
    public static Map<Id, String> getOpportunityApuracaoRendaNames(List<Id> opportunityIds) {
        try {
            Map<Id, String> result = new Map<Id, String>();
            if (opportunityIds == null || opportunityIds.isEmpty()) return result;

            Set<Id> visibleOpportunityIds = CommunicatorOpportunityAccessService.getVisibleOpportunityIds(
                new Set<Id>(opportunityIds)
            );
            if (visibleOpportunityIds.isEmpty()) return result;

            for (Opportunity opp : [
                SELECT Id, ApuracaoRenda__r.Name
                FROM Opportunity
                WHERE Id IN :visibleOpportunityIds
            ]) {
                result.put(
                    opp.Id,
                    (opp.ApuracaoRenda__r != null) ? opp.ApuracaoRenda__r.Name : null
                );
            }
            return result;
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    /**
     * @description Returns Opportunity.ApuracaoRenda__c (Id) + Opportunity.ApuracaoRenda__r.Name
     *              for the given Opportunity Ids. Used by LWC to create AR hyperlinks.
     * @param opportunityIds List of Opportunity Ids.
     * @return Map<OpportunityId, {id,name}>.
     */
    @AuraEnabled(cacheable=true)
    public static Map<Id, CommunicatorDTOs.IdNameDTO> getOpportunityApuracaoRendaRefs(List<Id> opportunityIds) {
        try {
            Map<Id, CommunicatorDTOs.IdNameDTO> result = new Map<Id, CommunicatorDTOs.IdNameDTO>();
            if (opportunityIds == null || opportunityIds.isEmpty()) return result;

            Set<Id> visibleOpportunityIds = CommunicatorOpportunityAccessService.getVisibleOpportunityIds(
                new Set<Id>(opportunityIds)
            );
            if (visibleOpportunityIds.isEmpty()) return result;

            for (Opportunity opp : [
                SELECT Id, ApuracaoRenda__c, ApuracaoRenda__r.Name
                FROM Opportunity
                WHERE Id IN :visibleOpportunityIds
            ]) {
                CommunicatorDTOs.IdNameDTO dto = new CommunicatorDTOs.IdNameDTO();
                dto.id   = (opp.ApuracaoRenda__c != null) ? String.valueOf(opp.ApuracaoRenda__c) : null;
                dto.name = (opp.ApuracaoRenda__r != null) ? opp.ApuracaoRenda__r.Name : null;
                result.put(opp.Id, dto);
            }
            return result;
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    /**
     * @description Returns AR / AB / Cotação refs for the given Opportunity Ids.
     */
    @AuraEnabled(cacheable=true)
    public static Map<Id, CommunicatorDTOs.OpportunityRelatedRefsDTO> getOpportunityRelatedRefs(List<Id> opportunityIds) {
        try {
            return CommunicatorThreadService.getOpportunityRelatedRefs(opportunityIds);
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    @AuraEnabled(cacheable=false)
    public static CommunicatorDTOs.OpportunityAccessRedirectDTO resolveOpportunityAccessRedirect(String opportunityId) {
        try {
            if (String.isBlank(opportunityId)) throw new CommunicatorException('Record ID cannot be blank.');
            Id parsedOpportunityId = (Id) opportunityId;
            String userLicenseName = getCurrentUserLicenseName();
            if (!isCurrentUserSalesforceLicense(userLicenseName)) {
                CommunicatorDTOs.OpportunityAccessRedirectDTO communityRedirect = buildNavigateRedirect(parsedOpportunityId, 'Opportunity');
                communityRedirect.forceCommunityDetailUrl = true;
                return communityRedirect;
            }
            if (!isCurrentUserSalesforcePlatform(userLicenseName)) return buildNavigateRedirect(parsedOpportunityId, 'Opportunity');
            return buildSalesforcePlatformRedirect(parsedOpportunityId);
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    private static CommunicatorDTOs.OpportunityAccessRedirectDTO buildSalesforcePlatformRedirect(Id opportunityId) {
        Map<Id, CommunicatorDTOs.OpportunityRelatedRefsDTO> refsByOppId =
            CommunicatorThreadService.getOpportunityRelatedRefs(new List<Id>{ opportunityId });
        CommunicatorDTOs.OpportunityRelatedRefsDTO refs = refsByOppId.get(opportunityId);
        if (canAccessAprovacaoBancaria(refs)) return buildNavigateRedirect((Id) refs.abId, 'AprovacaoBancaria__c');
        if (canAccessAnaliseFinanceira(refs)) return buildNavigateRedirect((Id) refs.arId, 'AnaliseFinanceira__c');
        return buildBlockedRedirect();
    }

    private static Boolean canAccessAprovacaoBancaria(CommunicatorDTOs.OpportunityRelatedRefsDTO refs) {
        if (refs == null || String.isBlank(refs.abId)) return false;
        if (!Schema.SObjectType.AprovacaoBancaria__c.isAccessible()) return false;
        return [SELECT COUNT() FROM AprovacaoBancaria__c WHERE Id = :refs.abId] > 0;
    }

    private static Boolean canAccessAnaliseFinanceira(CommunicatorDTOs.OpportunityRelatedRefsDTO refs) {
        if (refs == null || String.isBlank(refs.arId)) return false;
        if (!Schema.SObjectType.AnaliseFinanceira__c.isAccessible()) return false;
        return [SELECT COUNT() FROM AnaliseFinanceira__c WHERE Id = :refs.arId] > 0;
    }

    private static CommunicatorDTOs.OpportunityAccessRedirectDTO buildNavigateRedirect(Id recordId, String objectApiName) {
        CommunicatorDTOs.OpportunityAccessRedirectDTO dto = new CommunicatorDTOs.OpportunityAccessRedirectDTO();
        dto.action = 'navigateToRecord';
        dto.recordId = String.valueOf(recordId);
        dto.objectApiName = objectApiName;
        dto.message = null;
        dto.forceCommunityDetailUrl = false;
        return dto;
    }

    private static CommunicatorDTOs.OpportunityAccessRedirectDTO buildBlockedRedirect() {
        CommunicatorDTOs.OpportunityAccessRedirectDTO dto = new CommunicatorDTOs.OpportunityAccessRedirectDTO();
        dto.action = 'showNoAccess';
        dto.recordId = null;
        dto.objectApiName = null;
        dto.message = 'Você não tem permissão para ver o registro.';
        dto.forceCommunityDetailUrl = false;
        return dto;
    }

    private static String getCurrentUserLicenseName() {
        if (Test.isRunningTest() && useUserLicenseNameOverrideForTest == true) {
            return forceUserLicenseNameForTest;
        }
        try {
            User currentUser = [
                SELECT Profile.UserLicense.Name
                FROM User
                WHERE Id = :UserInfo.getUserId()
                LIMIT 1
            ];
            return currentUser.Profile.UserLicense.Name;
        } catch (Exception e) {
            return '';
        }
    }

    private static Boolean isCurrentUserSalesforcePlatform(String userLicenseName) {
        if (Test.isRunningTest() && useSalesforcePlatformOverrideForTest == true) {
            return forceSalesforcePlatformUserForTest == true;
        }
        return userLicenseName == 'Salesforce Platform';
    }

    private static Boolean isCurrentUserSalesforceLicense(String userLicenseName) {
        return userLicenseName == 'Salesforce';
    }

    /**
     * @description Returns the current stage/status of any SObject record by reading
     *              the field configured in CommunicatorConfig__mdt.StatusFieldApiName__c.
     *              Used by the history page to always reflect the record's live phase.
     * @param recordId   Id of any SObject.
     * @param objectType API name of the SObject (e.g. 'Opportunity'). Auto-resolved if blank.
     * @return Current stage value, or empty string if not configured.
     */
    @AuraEnabled(cacheable=false)
    public static String getRecordCurrentStage(String recordId, String objectType) {
        try {
            if (String.isBlank(recordId)) return '';
            String resolvedType = String.isBlank(objectType) ? '' : objectType;
            if (String.isBlank(resolvedType)) {
                try {
                    Id sfId = (Id) recordId;
                    resolvedType = sfId.getSObjectType().getDescribe().getName();
                } catch (Exception e) { resolvedType = ''; }
            }
            if (resolvedType == 'Repasse__c') {
                Map<Id, Repasse__c> repassesById = CommunicatorRepasseService.getRepassesByIds(new Set<Id>{ (Id) recordId });
                Repasse__c repasse = repassesById.get((Id) recordId);
                if (repasse == null) return '';
                if (isCurrentUserSalesforcePlatform(getCurrentUserLicenseName())
                    && !CommunicatorThreadService.isRepasseVisibleForCurrentUser(repasse)) {
                    return '';
                }
                String resolvedRecordId = CommunicatorThreadService.resolveOpportunityIdIfRepasse(recordId);
                if (!String.isBlank(resolvedRecordId) && resolvedRecordId != recordId) {
                    recordId = resolvedRecordId;
                    resolvedType = 'Opportunity';
                }
            }
            if (resolvedType == 'Opportunity') {
                List<Opportunity> opportunities = CommunicatorOpportunityDataService.getOpportunitiesByIds(
                    new Set<Id>{ (Id) recordId }
                );
                return opportunities.isEmpty() ? '' : String.valueOf(opportunities[0].StageName);
            }
            return CommunicatorRecordStatusService.getRecordStatus(recordId, resolvedType);
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

   
    // Repasse
   

    /**
     * @description Returns the current macro-phase of the latest Repasse linked to an Opportunity.
     *              Used by communicatorHistoryPage to auto-activate the correct Repasse phase tab.
     * @param opportunityId Id of the Opportunity.
     * @return Macro-phase label (e.g. 'Aguardando início'), or '' if no Repasse / unmapped.
     */
    @AuraEnabled(cacheable=false)
    public static String getRepasseMacroPhaseByOppId(String opportunityId) {
        try {
            if (String.isBlank(opportunityId)) return '';
            return CommunicatorRepassePhaseHelper.getRepasseMacroPhaseByOppId((Id) opportunityId);
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    /**
     * @description Returns the Id of the latest active Repasse linked to an Opportunity,
     *              only when the Repasse has a valid macro-phase.
     *              Used by assessoria users to redirect "Acessar oportunidade" to the Repasse record.
     * @param opportunityId Id of the Opportunity.
     * @return Repasse Id string when a valid Repasse + macro-phase exists; null otherwise.
     */
    @AuraEnabled(cacheable=false)
    public static String getRepasseIdByOppId(String opportunityId) {
        try {
            if (String.isBlank(opportunityId)) return null;
            Id oppId = (Id) opportunityId;
            Map<Id, Repasse__c> repassesByOppId = CommunicatorThreadService.getVisibleLatestRepassesByOpportunityIds(
                new Set<Id>{ oppId }
            );
            Repasse__c repasse = repassesByOppId.get(oppId);
            if (repasse == null) return null;
            String sinteseName = CommunicatorRepassePhaseHelper.getRepasseSinteseName(repasse);
            if (String.isBlank(sinteseName)) return null;
            String macroPhase = CommunicatorRepassePhaseHelper.getMacroPhase(sinteseName);
            if (String.isBlank(macroPhase)) return null;
            return String.valueOf(repasse.Id);
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    /**
     * @description Ensures a CommunicatorThread__c exists for the given Opportunity + Repasse macro-phase.
     *              Creates one if absent. Returns the thread Id as String.
     */
    @AuraEnabled(cacheable=false)
    public static String ensureRepasseThread(String opportunityId, String macroPhase) {
        try {
            if (String.isBlank(opportunityId) || String.isBlank(macroPhase)) return null;
            Id threadId = CommunicatorThreadService.ensureThreadForRepassePhase(
                (Id) opportunityId, macroPhase
            );
            return threadId;
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    @AuraEnabled(cacheable=false)
    public static String getOpportunityIdForAnaliseFinanceira(Id afId) {
        try {
            return CommunicatorThreadService.resolveOpportunityIdForAnaliseFinanceira(afId);
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    @AuraEnabled(cacheable=false)
    public static String resolveOpportunityId(Id recordId, String objectApiName) {
        try {
            return CommunicatorThreadService.resolveOpportunityIdForRecord(recordId, objectApiName);
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

   
    // Configuration
   

    /**
     * @description Returns all Communicator settings from CommunicatorConfig__mdt.
     *              Cached per transaction. Used by LWC to read config on init.
     */
    @AuraEnabled(cacheable=true)
    public static CommunicatorDTOs.SettingsDTO getSettings() {
        try {
            CommunicatorDTOs.SettingsDTO dto = new CommunicatorDTOs.SettingsDTO();
            dto.objectApiNames    = CommunicatorConfigService.getObjectApiNames();
            dto.filterOpenOnly    = CommunicatorConfigService.getFilterOpenOnly();
            dto.maxSearchResults  = CommunicatorConfigService.getMaxSearchResults();
            dto.maxRecentRecords  = CommunicatorConfigService.getMaxRecentRecords();
            dto.pollingIntervalMs = CommunicatorConfigService.getPollingIntervalMs();
            dto.messagesPerPage   = CommunicatorConfigService.getMessagesPerPage();
            dto.threadsPerPage    = CommunicatorConfigService.getThreadsPerPage();
            dto.hasGroupAccess                = FeatureManagement.checkPermission('CommunicatorChatGroup');
            dto.isSalesforcePlatformUser      = isCurrentUserSalesforcePlatform(getCurrentUserLicenseName());
            dto.hasCommunicatorChatPermission = hasCommunicatorChatPermission();
            dto.noPermissionMessage           = CommunicatorConfigService.getMensagemErroSemPermissao();
            dto.chatterHistoryEmptyMessage    = CommunicatorConfigService.getChatterHistoryEmptyMessage();
            dto.maxUploadFileSizeMB           = CommunicatorConfigService.getMaxUploadFileSizeMB();
            dto.uploadFileSizeErrorMessage    = CommunicatorConfigService.getMensagemErroArquivoGrande();
            return dto;
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    /**
     * @description Validates uploaded files against the configured size limit.
     *              Files exceeding the limit are deleted from Salesforce Content.
     *              Returns valid document IDs and names of rejected files.
     * @param contentDocumentIds List of ContentDocument IDs to validate.
     * @return UploadValidationResultDTO with valid IDs, rejected names and error message.
     */
    @AuraEnabled(cacheable=false)
    public static CommunicatorDTOs.UploadValidationResultDTO validateUploadedFiles(
        List<String> contentDocumentIds
    ) {
        try {
            CommunicatorDTOs.UploadValidationResultDTO result = new CommunicatorDTOs.UploadValidationResultDTO();
            result.validContentDocumentIds = new List<String>();
            result.rejectedFileNames       = new List<String>();
            Integer maxMB = CommunicatorConfigService.getMaxUploadFileSizeMB();
            result.errorMessage            = CommunicatorConfigService.getMensagemErroArquivoGrande()
                                             + ' (Limite: ' + maxMB + ' MB)';

            if (contentDocumentIds == null || contentDocumentIds.isEmpty()) return result;

            Set<Id> requestedDocumentIds = new Set<Id>();
            for (String contentDocumentId : contentDocumentIds) {
                if (String.isNotBlank(contentDocumentId)) requestedDocumentIds.add((Id) contentDocumentId);
            }
            if (!CommunicatorBroadcastService.getBroadcastDocumentIds(requestedDocumentIds).isEmpty()) {
                throw new CommunicatorException('Use a API específica de comunicados.');
            }

            Long maxSizeBytes = (Long) maxMB * 1024 * 1024;

            List<ContentVersion> versions = [
                SELECT ContentDocumentId, ContentSize, Title
                FROM   ContentVersion
                WHERE  ContentDocumentId IN :contentDocumentIds
                AND    IsLatest = true
            ];

            Set<Id> oversizedIds = new Set<Id>();
            for (ContentVersion cv : versions) {
                if (cv.ContentSize > maxSizeBytes) {
                    oversizedIds.add(cv.ContentDocumentId);
                    result.rejectedFileNames.add(cv.Title);
                } else {
                    result.validContentDocumentIds.add(String.valueOf(cv.ContentDocumentId));
                }
            }

            if (!oversizedIds.isEmpty()) {
                delete [SELECT Id FROM ContentDocument WHERE Id IN :oversizedIds];
            }

            return result;
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    private static Boolean hasCommunicatorChatPermission() {
        if (Test.isRunningTest() && forceHasCommunicatorChatPermissionForTest != null) {
            return forceHasCommunicatorChatPermissionForTest;
        }
        return FeatureManagement.checkPermission('CommunicatorChat');
    }

    
    // Multi-object record search
   

    /**
     * @description Searches for records across all configured SObject types.
     * @param keyword Search term.
     * @return List of CommunicatorDTOs.RecordResultDTO grouped by object type.
     */
    @AuraEnabled(cacheable=false)
    public static List<CommunicatorDTOs.RecordResultDTO> searchRecords(String keyword) {
        try {
            return CommunicatorRecordSearchService.searchRecords(keyword);
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

   
    // Mentions
   

    /**
     * @description Returns mention candidates for the @mention picker.
     *              Includes thread participants (users) and all active groups.
     */
    @AuraEnabled(cacheable=false)
    public static List<CommunicatorDTOs.MentionCandidateDTO> getMentionCandidates(
        Id threadId, String keyword
    ) {
        try {
            CommunicatorBroadcastService.assertConventionalThread(threadId);
            return CommunicatorMentionService.getMentionCandidates(threadId, keyword);
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    @AuraEnabled(cacheable=false)
    public static Map<String, String> getMentionUserNames(List<Id> userIds) {
        try {
            return CommunicatorMentionService.getUserNamesByIds(userIds);
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

   
    // Groups
   

    @AuraEnabled(cacheable=false)
    public static List<CommunicatorDTOs.GroupListItemDTO> getGroupsWithStats() {
        try {
            return CommunicatorGroupService.getGroupsWithStatsForUser();
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    /**
     * @description Searches for users below the current user in the role hierarchy.
     *              Returns empty list when keyword < 3 chars or user has no role.
     */
    @AuraEnabled(cacheable=true)
    public static List<CommunicatorDTOs.UserResultDTO> searchSubordinateUsers(String keyword) {
        try {
            return CommunicatorGroupService.searchSubordinateUsers(keyword);
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    /**
     * @description Creates a group and atomically adds all selected members.
     *              The creator is always added automatically by createGroup().
     */
    @AuraEnabled(cacheable=false)
    public static CommunicatorGroup__c createGroupWithMembers(String name, List<Id> memberIds) {
        try {
            if (!hasGroupCreatePermission()) {
                throw new AuraHandledException('Você não possui permissão para criar grupos.');
            }
            Set<Id> memberIdsToValidate = sanitizeTraditionalGroupCandidateUserIds(memberIds, true);
            CommunicatorGroupService.assertTraditionalGroupUsersCanBeAdded(memberIdsToValidate);
            CommunicatorGroup__c grp = CommunicatorGroupService.createGroup(name, null);
            if (!memberIdsToValidate.isEmpty()) {
                CommunicatorGroupService.addMembers(grp.Id, memberIdsToValidate);
            }
            return grp;
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    @AuraEnabled(cacheable=false)
    public static List<CommunicatorGroup__c> getActiveGroups() {
        try {
            return CommunicatorGroupService.getActiveGroups();
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    @AuraEnabled(cacheable=false)
    public static CommunicatorGroup__c createGroup(String name, String description) {
        try {
            if (!hasGroupCreatePermission()) {
                throw new AuraHandledException('Você não possui permissão para criar grupos.');
            }
            return CommunicatorGroupService.createGroup(name, description);
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    @AuraEnabled(cacheable=false)
    public static void addGroupMember(Id groupId, Id userId) {
        try {
            CommunicatorBroadcastService.assertConventionalGroup(groupId);
            CommunicatorGroupService.assertTraditionalGroupUsersCanBeAdded(new Set<Id>{ userId });
            CommunicatorGroupService.addMember(groupId, userId);
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    @AuraEnabled(cacheable=false)
    public static void removeGroupMember(Id groupId, Id userId) {
        try {
            if (groupId == null) {
                return;
            }
            CommunicatorBroadcastService.assertConventionalGroup(groupId);
            CommunicatorGroupService.removeMember(groupId, userId);
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    @AuraEnabled(cacheable=false)
    public static void deleteGroupAndMembers(String groupId) {
        try {
            CommunicatorBroadcastService.assertConventionalGroup((Id) groupId);
            CommunicatorGroupService.deleteGroupAndMembers((Id) groupId);
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    @AuraEnabled(cacheable=false)
    public static List<CommunicatorGroupMember__c> getGroupMembers(Id groupId) {
        try {
            CommunicatorBroadcastService.assertConventionalGroup(groupId);
            return CommunicatorGroupService.getGroupMembers(groupId);
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    @AuraEnabled(cacheable=false)
    public static List<CommunicatorDTOs.GroupMemberDTO> getGroupMembersAsDTO(Id groupId) {
        try {
            CommunicatorBroadcastService.assertConventionalGroup(groupId);
            return CommunicatorGroupService.getGroupMembersAsDTOs(groupId);
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    @AuraEnabled(cacheable=false)
    public static void saveGroupDetails(
        String groupId,
        String newName,
        List<Id> removedMemberIds,
        List<Id> addedMemberUserIds
    ) {
        try {
            CommunicatorBroadcastService.assertConventionalGroup((Id) groupId);
            CommunicatorGroupService.assertTraditionalGroupUsersCanBeAdded(
                sanitizeTraditionalGroupCandidateUserIds(addedMemberUserIds, false)
            );
            CommunicatorGroupService.saveGroupDetails(
                (Id) groupId,
                newName,
                removedMemberIds,
                addedMemberUserIds
            );
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

   
    // Notification read status
   

    @AuraEnabled(cacheable=false)
    public static Integer getUnreadMentionCount(Id threadId) {
        try {
            CommunicatorBroadcastService.assertConventionalThread(threadId);
            return CommunicatorNotificationRecordService.getUnreadMentionCount(threadId);
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

   
    // Current user
   

    @AuraEnabled(cacheable=true)
    public static String getCurrentUserName() {
        return UserInfo.getName();
    }

    @AuraEnabled(cacheable=false)
    public static List<CommunicatorDTOs.SourceThreadInfoDTO> getSourceThreadsInfo(List<Id> threadIds) {
        try {
            return CommunicatorThreadService.getSourceThreadsInfo(
                new List<Id>(CommunicatorBroadcastService.filterConventionalThreadIds(threadIds))
            );
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

   
    // Group thread
   

    @AuraEnabled(cacheable=false)
    public static CommunicatorThread__c getOrCreateGroupThread(Id groupId) {
        try {
            CommunicatorBroadcastService.assertConventionalGroup(groupId);
            return CommunicatorThreadService.getOrCreateGroupThread(groupId);
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    @AuraEnabled(cacheable=false)
    public static CommunicatorMessage__c sendGroupMessage(Id groupId, String messageBody, Id sourceMessageId) {
        try {
            CommunicatorBroadcastService.assertConventionalGroup(groupId);
            return CommunicatorMessageService.sendGroupMessage(groupId, messageBody, sourceMessageId);
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    @AuraEnabled(cacheable=false)
    public static List<Map<String, String>> getRecentlyViewedThreads(Integer maxCount) {
        try {
            Integer limitCount = (maxCount != null && maxCount > 0) ? maxCount : 5;

            // Step 1 — get recently viewed thread IDs in LastViewedDate order
            List<Id> threadIds = new List<Id>();
            for (RecentlyViewed rv : [
                SELECT Id
                FROM RecentlyViewed
                WHERE Type = 'CommunicatorThread__c'
                ORDER BY LastViewedDate DESC
                LIMIT :limitCount
            ]) {
                threadIds.add(rv.Id);
            }
            if (threadIds.isEmpty()) return new List<Map<String, String>>();

            // Step 2 — fetch thread RecordId__c.
            // No WITH SECURITY_ENFORCED: controller is without sharing and RecentlyViewed
            // is already user-scoped, so Platform users can access their own viewed threads.
            Map<Id, CommunicatorThread__c> threadMap = new Map<Id, CommunicatorThread__c>(
                [SELECT Id, RecordId__c FROM CommunicatorThread__c
                 WHERE Id IN :threadIds]
            );

            // Step 2.5 — for Platform (assessoria) users, reuse the Opportunity/card
            // visibility predicate from the main list instead of the narrower thread-only
            // filter. This keeps MRU aligned with cards the user can already open.
            Set<Id> accessibleThreadIds = CommunicatorThreadService.filterRecentlyViewedThreadIdsForCurrentUser(
                new Set<Id>(threadIds)
            );
            accessibleThreadIds.removeAll(
                CommunicatorBroadcastService.getBroadcastThreadIds(accessibleThreadIds)
            );
            List<Id> filteredThreadIds = new List<Id>();
            for (Id tid : threadIds) {
                if (accessibleThreadIds.contains(tid)) filteredThreadIds.add(tid);
            }
            threadIds = filteredThreadIds;
            if (threadIds.isEmpty()) return new List<Map<String, String>>();

            // Step 3 — fetch Opportunity names in one query
            Set<Id> oppIds = new Set<Id>();
            Map<Id, Id> opportunityIdByThreadId = new Map<Id, Id>();
            for (Id threadId : threadIds) {
                CommunicatorThread__c threadRecord = threadMap.get(threadId);
                if (threadRecord == null || String.isBlank(threadRecord.RecordId__c)) continue;
                Id opportunityId = CommunicatorThreadService.resolveOpportunityIdForThreadRecord(
                    threadRecord.RecordId__c
                );
                if (opportunityId == null) continue;
                oppIds.add(opportunityId);
                opportunityIdByThreadId.put(threadId, opportunityId);
            }
            Map<Id, String> oppNames = new Map<Id, String>();
            if (!oppIds.isEmpty()) {
                for (Opportunity opp : [SELECT Id, Name FROM Opportunity
                                        WHERE Id IN :oppIds]) {
                    oppNames.put(opp.Id, opp.Name);
                }
            }

            // Step 4 — build result preserving RecentlyViewed order, deduplicating by Opportunity
            List<Map<String, String>> result = new List<Map<String, String>>();
            Set<Id> seenOppIds = new Set<Id>();
            for (Id threadId : threadIds) {
                Id opportunityId = opportunityIdByThreadId.get(threadId);
                if (opportunityId == null) continue;
                if (seenOppIds.contains(opportunityId)) continue;
                seenOppIds.add(opportunityId);
                result.add(new Map<String, String>{
                    'id'       => (String) opportunityId,
                    'name'     => oppNames.containsKey(opportunityId) ? oppNames.get(opportunityId) : '',
                    'threadId' => (String) threadId
                });
            }
            return result;
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    @AuraEnabled(cacheable=false)
    public static List<CommunicatorDTOs.ThreadListItemDTO> getRecentlyViewedThreadCards(Integer maxCount) {
        try {
            List<Id> threadIds = getRecentlyViewedUniqueThreadIdsForCards(maxCount);
            return CommunicatorThreadService.getThreadCardsByRecentOrder(threadIds, maxCount);
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    private static List<Id> getRecentlyViewedUniqueThreadIdsForCards(Integer maxCount) {
        Integer resultLimit = (maxCount != null && maxCount > 0) ? maxCount : 5;
        if (resultLimit > 2000) resultLimit = 2000;
        Integer candidateLimit = resultLimit * 5;
        if (candidateLimit > 200) candidateLimit = 200;

        List<Id> candidateThreadIds = new List<Id>();
        for (RecentlyViewed rv : [
            SELECT Id
            FROM RecentlyViewed
            WHERE Type = 'CommunicatorThread__c'
            ORDER BY LastViewedDate DESC
            LIMIT :candidateLimit
        ]) {
            candidateThreadIds.add(rv.Id);
        }
        if (candidateThreadIds.isEmpty()) return new List<Id>();

        Map<Id, CommunicatorThread__c> threadMap = new Map<Id, CommunicatorThread__c>([
            SELECT Id, RecordId__c
            FROM CommunicatorThread__c
            WHERE Id IN :candidateThreadIds
        ]);

        Set<Id> accessibleThreadIds = CommunicatorThreadService.filterRecentlyViewedThreadIdsForCurrentUser(
            new Set<Id>(candidateThreadIds)
        );
        accessibleThreadIds.removeAll(
            CommunicatorBroadcastService.getBroadcastThreadIds(accessibleThreadIds)
        );

        List<Id> resultThreadIds = new List<Id>();
        Set<Id> seenOpportunityIds = new Set<Id>();
        for (Id threadId : candidateThreadIds) {
            if (!accessibleThreadIds.contains(threadId)) continue;

            CommunicatorThread__c threadRecord = threadMap.get(threadId);
            if (threadRecord == null || String.isBlank(threadRecord.RecordId__c)) continue;

            Id opportunityId = CommunicatorThreadService.resolveOpportunityIdForThreadRecord(
                threadRecord.RecordId__c
            );
            if (opportunityId == null || seenOpportunityIds.contains(opportunityId)) continue;

            seenOpportunityIds.add(opportunityId);
            resultThreadIds.add(threadId);
            if (resultThreadIds.size() >= resultLimit) break;
        }

        return resultThreadIds;
    }

    @AuraEnabled(cacheable=false)
    public static void markThreadAsRecentlyViewed(Id threadId) {
        try {
            if (threadId == null) return;
            CommunicatorBroadcastService.assertConventionalThread(threadId);
            // Use dynamic SOQL so orgs that support MRU tracking keep the behavior,
            // while orgs that don't can safely ignore the request without blocking deploys.
            String threadIdValue = String.valueOf(threadId);
            String soql =
                'SELECT Id FROM CommunicatorThread__c WHERE Id = \'' +
                String.escapeSingleQuotes(threadIdValue) +
                '\' FOR VIEW';
            Database.query(soql);
        } catch (Exception ex) {
            String message = ex == null ? null : ex.getMessage();
            if (message != null && message.contains('viewing is tracked')) {
                return;
            }
            throw buildAuraHandledException(ex);
        }
    }

    // ─────────────────────────────────────────
    // Broadcast
    // ─────────────────────────────────────────

    @AuraEnabled(cacheable=false)
    public static CommunicatorGroup__c createBroadcast(
        String name,
        String description,
        List<CommunicatorBroadcastAudience__c> audiences
    ) {
        try {
            return CommunicatorBroadcastService.createBroadcast(name, description, audiences);
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    @AuraEnabled(cacheable=false)
    public static CommunicatorDTOs.BroadcastAuthoringContextDTO getBroadcastAuthoringContext() {
        try {
            return CommunicatorBroadcastService.getBroadcastAuthoringContext();
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    @AuraEnabled(cacheable=false)
    public static void replaceBroadcastAudience(
        Id broadcastGroupId,
        List<CommunicatorBroadcastAudience__c> audiences
    ) {
        try {
            CommunicatorBroadcastService.replaceBroadcastAudience(broadcastGroupId, audiences);
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    @AuraEnabled(cacheable=false)
    public static CommunicatorDTOs.BroadcastDetailsDTO getBroadcastDetails(Id broadcastGroupId) {
        try {
            return CommunicatorBroadcastService.getBroadcastDetails(broadcastGroupId);
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    @AuraEnabled(cacheable=false)
    public static CommunicatorGroup__c saveBroadcastDetails(
        Id broadcastGroupId,
        String name,
        String description,
        List<CommunicatorBroadcastAudience__c> audiences
    ) {
        try {
            return CommunicatorBroadcastAudienceService.saveBroadcastDetailsForLwc(
                broadcastGroupId,
                name,
                description,
                audiences
            );
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    @AuraEnabled(cacheable=false)
    public static CommunicatorGroup__c archiveBroadcast(Id broadcastGroupId) {
        try {
            return CommunicatorBroadcastAudienceService.archiveBroadcastGroup(broadcastGroupId);
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    @AuraEnabled(cacheable=false)
    public static List<CommunicatorDTOs.UserResultDTO> searchBroadcastAudienceTargets(
        String audienceType,
        String keyword,
        Integer limitSize
    ) {
        try {
            return CommunicatorBroadcastAudienceService.searchBroadcastAudienceTargets(
                audienceType,
                keyword,
                limitSize
            );
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    @AuraEnabled(cacheable=false)
    public static CommunicatorDTOs.BroadcastListPageDTO getBroadcastList(
        Integer pageSize,
        String cursor
    ) {
        try {
            return CommunicatorBroadcastService.getBroadcastList(pageSize, cursor);
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    @AuraEnabled(cacheable=false)
    public static List<CommunicatorDTOs.BroadcastListItemDTO> getBroadcastDrafts() {
        try {
            return CommunicatorBroadcastService.getBroadcastDrafts();
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    @AuraEnabled(cacheable=false)
    public static CommunicatorDTOs.BroadcastThreadDTO getBroadcastThread(Id broadcastGroupId) {
        try {
            return CommunicatorBroadcastService.getBroadcastThread(broadcastGroupId);
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    @AuraEnabled(cacheable=false)
    public static List<CommunicatorDTOs.BroadcastMessageDTO> getBroadcastMessages(
        Id threadId,
        Integer pageSize,
        Integer offsetVal
    ) {
        try {
            return CommunicatorBroadcastService.getBroadcastMessageViews(threadId, pageSize, offsetVal);
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    @AuraEnabled(cacheable=false)
    public static Integer getBroadcastMessageCount(Id threadId) {
        try {
            return CommunicatorBroadcastService.getBroadcastMessageCount(threadId);
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    @AuraEnabled(cacheable=false)
    public static Integer getBroadcastMessageOffset(Id threadId, Id messageId) {
        try {
            return CommunicatorBroadcastService.getBroadcastMessageOffset(threadId, messageId);
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    @AuraEnabled(cacheable=false)
    public static CommunicatorDTOs.BroadcastPollPageDTO pollBroadcastMessages(
        Id threadId,
        String cursor
    ) {
        try {
            return CommunicatorBroadcastService.pollBroadcastMessages(threadId, cursor);
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    @AuraEnabled(cacheable=false)
    public static List<CommunicatorDTOs.BroadcastMessageDTO> searchBroadcastMessages(
        Id threadId,
        String keyword
    ) {
        try {
            return CommunicatorBroadcastService.searchBroadcastMessageViews(threadId, keyword);
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    @AuraEnabled(cacheable=false)
    public static CommunicatorDTOs.BroadcastMessageDTO publishBroadcastMessage(
        Id broadcastGroupId,
        String messageSubject,
        String messageBody,
        List<Id> contentDocumentIds
    ) {
        try {
            CommunicatorMessage__c publishedMessage = CommunicatorBroadcastService.publishBroadcastMessageForLwc(
                broadcastGroupId,
                messageSubject,
                messageBody,
                contentDocumentIds
            );
            return CommunicatorBroadcastService.getBroadcastMessageView(publishedMessage.Id);
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    @AuraEnabled(cacheable=false)
    public static CommunicatorDTOs.BroadcastMessageDTO retryBroadcastDistribution(Id messageId) {
        try {
            CommunicatorMessage__c retriedMessage =
                CommunicatorBroadcastService.retryBroadcastDistribution(messageId);
            return CommunicatorBroadcastService.getBroadcastMessageView(retriedMessage.Id);
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    @AuraEnabled(cacheable=false)
    public static CommunicatorDTOs.BroadcastMessageDTO editBroadcastMessage(
        Id messageId,
        String messageSubject,
        String messageBody,
        List<Id> newContentDocumentIds,
        List<Id> removedContentDocumentIds
    ) {
        try {
            CommunicatorMessage__c editedMessage = CommunicatorBroadcastService.editBroadcastMessage(
                messageId,
                messageSubject,
                messageBody,
                newContentDocumentIds,
                removedContentDocumentIds
            );
            return CommunicatorBroadcastService.getBroadcastMessageView(editedMessage.Id);
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    public static CommunicatorDTOs.BroadcastMessageDTO editBroadcastMessage(
        Id messageId,
        String messageSubject,
        String messageBody
    ) {
        return editBroadcastMessage(messageId, messageSubject, messageBody, null, null);
    }

    @AuraEnabled(cacheable=false)
    public static Integer getBroadcastUnreadCount(Id threadId) {
        try {
            return CommunicatorBroadcastService.getBroadcastUnreadCount(threadId);
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    @AuraEnabled(cacheable=false)
    public static Integer getBroadcastUnreadTotal() {
        try {
            return CommunicatorBroadcastService.getBroadcastUnreadTotal();
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    @AuraEnabled(cacheable=false)
    public static Map<String, Integer> getBroadcastUnreadCountsByThread(List<Id> threadIds) {
        try {
            Map<String, Integer> result = new Map<String, Integer>();
            Map<Id, Integer> unreadByThread =
                CommunicatorBroadcastService.getBroadcastUnreadCountsByThread(
                    threadIds == null ? new Set<Id>() : new Set<Id>(threadIds)
                );
            for (Id threadId : unreadByThread.keySet()) {
                result.put(String.valueOf(threadId), unreadByThread.get(threadId));
            }
            return result;
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    @AuraEnabled(cacheable=false)
    public static void markBroadcastAsRead(Id threadId) {
        try {
            CommunicatorBroadcastService.markBroadcastAsRead(threadId);
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    @AuraEnabled(cacheable=false)
    public static CommunicatorDTOs.UploadValidationResultDTO validateBroadcastUploadedFiles(
        Id broadcastGroupId,
        List<String> contentDocumentIds
    ) {
        try {
            return CommunicatorBroadcastService.validateBroadcastUploadedFiles(
                broadcastGroupId, contentDocumentIds
            );
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    @AuraEnabled(cacheable=false)
    public static CommunicatorDTOs.MessageAttachmentDTO uploadBroadcastTemporaryAttachmentFromBase64(
        Id broadcastGroupId,
        String fileName,
        String base64Data,
        String contentType
    ) {
        try {
            return CommunicatorBroadcastService.uploadBroadcastTemporaryAttachmentFromBase64(
                broadcastGroupId,
                fileName,
                base64Data,
                contentType
            );
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    @AuraEnabled(cacheable=false)
    public static List<CommunicatorDTOs.MessageAttachmentDTO> getBroadcastMessageAttachments(
        Id threadId,
        List<Id> messageIds
    ) {
        try {
            return CommunicatorBroadcastService.getBroadcastMessageAttachments(threadId, messageIds);
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    @AuraEnabled(cacheable=false)
    public static CommunicatorDTOs.AttachmentFileDTO getBroadcastAttachmentFile(
        Id threadId,
        Id messageId,
        String contentDocumentId,
        String contentVersionId
    ) {
        try {
            return CommunicatorBroadcastService.getBroadcastAttachmentFile(
                threadId, messageId, contentDocumentId, contentVersionId
            );
        } catch (Exception ex) { throw buildAuraHandledException(ex); }
    }

    private static AuraHandledException buildAuraHandledException(Exception ex) {
        return new AuraHandledException(ex == null ? 'Unexpected error.' : ex.getMessage());
    }

    private static Set<Id> sanitizeTraditionalGroupCandidateUserIds(List<Id> userIds, Boolean excludeCurrentUser) {
        Set<Id> result = new Set<Id>();
        if (userIds != null) {
            result.addAll(userIds);
        }
        result.remove(null);
        if (excludeCurrentUser == true) {
            result.remove(UserInfo.getUserId());
        }
        return result;
    }

}