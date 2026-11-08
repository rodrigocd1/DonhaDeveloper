/**
 * @description Ensures communicator attachments remain accessible in Experience/Partner contexts.
 *              Applies "AllUsers" visibility to non-User links for ContentDocuments used by
 *              CommunicatorMessage__c attachment messages.
 *
 *              Uses without sharing so that visibility repairs can always be applied regardless
 *              of the calling user's record-level permissions (e.g. partner community users).
 */
public without sharing class CommunicatorFileShareService {

    /**
     * @description Resolves latest published ContentVersion Ids for the provided ContentDocument Ids.
     */
    public static Map<String, String> getLatestVersionIds(List<String> contentDocumentIds) {
        Map<String, String> versionIdsByDocumentId = new Map<String, String>();
        if (contentDocumentIds == null || contentDocumentIds.isEmpty()) return versionIdsByDocumentId;

        Set<Id> docIds = new Set<Id>();
        for (String rawId : contentDocumentIds) {
            if (String.isBlank(rawId)) continue;
            try {
                Id docId = (Id) rawId;
                if (String.valueOf(docId).startsWith('069')) {
                    docIds.add(docId);
                }
            } catch (Exception ex) {
                // Ignore malformed ids; timeline will fall back to document download.
            }
        }
        if (docIds.isEmpty()) return versionIdsByDocumentId;

        for (ContentDocument doc : [
            SELECT Id, LatestPublishedVersionId
            FROM ContentDocument
            WHERE Id IN :docIds
        ]) {
            if (doc.LatestPublishedVersionId != null) {
                versionIdsByDocumentId.put(
                    String.valueOf(doc.Id),
                    String.valueOf(doc.LatestPublishedVersionId)
                );
            }
        }

        return versionIdsByDocumentId;
    }

    /**
     * @description Ensures Network-level CDL exists for each document so that authenticated
     *              Experience Cloud partner users can download them via servlet.shepherd.
     *              Called lazily when the timeline loads attachment version IDs.
     */
    public static void repairNetworkAccess(List<String> contentDocumentIds) {
        repairNetworkAccessInternal(contentDocumentIds, Network.getNetworkId());
    }

    @TestVisible
    private static void repairNetworkAccessInternal(List<String> contentDocumentIds, Id networkId) {
        if (networkId == null) return;
        if (contentDocumentIds == null || contentDocumentIds.isEmpty()) return;

        Set<Id> docIds = new Set<Id>();
        for (String rawId : contentDocumentIds) {
            if (String.isBlank(rawId)) continue;
            try { docIds.add((Id) rawId); } catch (Exception ex) { /* skip malformed */ }
        }
        if (docIds.isEmpty()) return;

        Set<Id> docsWithNetworkLink = new Set<Id>();
        for (ContentDocumentLink link : [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE ContentDocumentId IN :docIds
              AND LinkedEntityId = :networkId
        ]) {
            docsWithNetworkLink.add(link.ContentDocumentId);
        }

        List<ContentDocumentLink> inserts = new List<ContentDocumentLink>();
        for (Id docId : docIds) {
            if (!docsWithNetworkLink.contains(docId)) {
                inserts.add(new ContentDocumentLink(
                    ContentDocumentId = docId,
                    LinkedEntityId    = networkId,
                    ShareType         = 'V',
                    Visibility        = 'AllUsers'
                ));
            }
        }
        if (!inserts.isEmpty()) {
            Database.insert(inserts, false);
        }
    }

    /**
     * @description Called during message send with attachment.
     *              Ensures a thread link and a Network link exist, and normalizes visibility
     *              for all non-User links so partner community users can access the file.
     */
    public static void ensureAccessForAttachment(Id contentDocumentId, Id threadId) {
        ensureAccessForAttachmentInternal(contentDocumentId, threadId, Network.getNetworkId(), null);
    }

    /**
     * @description Same as ensureAccessForAttachment, but also guarantees a link to Opportunity.
     */
    public static void ensureAccessForAttachment(Id contentDocumentId, Id threadId, Id opportunityId) {
        ensureAccessForAttachmentInternal(contentDocumentId, threadId, Network.getNetworkId(), opportunityId);
    }

    /**
     * @description Bulk equivalent of ensureAccessForAttachment for multiple ContentDocuments.
     */
    public static void ensureAccessForAttachments(List<Id> contentDocumentIds, Id threadId) {
        ensureAccessForAttachmentsInternal(contentDocumentIds, threadId, Network.getNetworkId(), null);
    }

    /**
     * @description Bulk equivalent of ensureAccessForAttachment that also guarantees Opportunity links.
     */
    public static void ensureAccessForAttachments(
        List<Id> contentDocumentIds,
        Id threadId,
        Id opportunityId
    ) {
        ensureAccessForAttachmentsInternal(
            contentDocumentIds,
            threadId,
            Network.getNetworkId(),
            opportunityId
        );
    }

    @TestVisible
    private static void ensureAccessForAttachmentInternal(Id contentDocumentId, Id threadId, Id networkId) {
        ensureAccessForAttachmentInternal(contentDocumentId, threadId, networkId, null);
    }

    @TestVisible
    private static void ensureAccessForAttachmentInternal(
        Id contentDocumentId,
        Id threadId,
        Id networkId,
        Id opportunityId
    ) {
        ensureAccessForAttachmentsInternal(
            contentDocumentId == null ? null : new List<Id>{ contentDocumentId },
            threadId,
            networkId,
            opportunityId
        );
    }

    @TestVisible
    private static void ensureAccessForAttachmentsInternal(
        List<Id> contentDocumentIds,
        Id threadId,
        Id networkId,
        Id opportunityId
    ) {
        if (threadId == null || contentDocumentIds == null || contentDocumentIds.isEmpty()) return;

        Set<Id> documentIds = new Set<Id>();
        for (Id contentDocumentId : contentDocumentIds) {
            if (contentDocumentId != null) {
                documentIds.add(contentDocumentId);
            }
        }
        if (documentIds.isEmpty()) return;

        Map<Id, List<ContentDocumentLink>> linksByDocumentId = new Map<Id, List<ContentDocumentLink>>();
        for (Id contentDocumentId : documentIds) {
            linksByDocumentId.put(contentDocumentId, new List<ContentDocumentLink>());
        }
        for (ContentDocumentLink link : [
            SELECT Id, ContentDocumentId, LinkedEntityId, ShareType, Visibility
            FROM ContentDocumentLink
            WHERE ContentDocumentId IN :documentIds
        ]) {
            linksByDocumentId.get(link.ContentDocumentId).add(link);
        }

        List<ContentDocumentLink> updates = new List<ContentDocumentLink>();
        List<ContentDocumentLink> inserts = new List<ContentDocumentLink>();
        for (Id contentDocumentId : documentIds) {
            AttachmentLinkState state = inspectExistingLinks(
                linksByDocumentId.get(contentDocumentId),
                threadId,
                networkId,
                opportunityId
            );
            updates.addAll(state.updates);
            inserts.addAll(buildMissingLinks(
                contentDocumentId,
                threadId,
                networkId,
                opportunityId,
                state
            ));
        }

        if (!updates.isEmpty()) update updates;
        if (!inserts.isEmpty()) Database.insert(inserts, false);
    }

    private class AttachmentLinkState {
        Boolean hasThreadLink = false;
        Boolean hasNetworkLink = false;
        Boolean hasOpportunityLink = false;
        List<ContentDocumentLink> updates = new List<ContentDocumentLink>();
    }

    private static AttachmentLinkState inspectExistingLinks(
        List<ContentDocumentLink> links,
        Id threadId,
        Id networkId,
        Id opportunityId
    ) {
        AttachmentLinkState state = new AttachmentLinkState();
        for (ContentDocumentLink link : links) {
            if (link.LinkedEntityId == threadId) state.hasThreadLink = true;
            if (networkId != null && link.LinkedEntityId == networkId) state.hasNetworkLink = true;
            if (opportunityId != null && link.LinkedEntityId == opportunityId) state.hasOpportunityLink = true;
            if (mustNormalizeVisibility(link)) {
                link.Visibility = 'AllUsers';
                link.ShareType = 'V';
                state.updates.add(link);
            }
        }
        return state;
    }

    private static Boolean mustNormalizeVisibility(ContentDocumentLink link) {
        return link.LinkedEntityId != null
            && link.LinkedEntityId.getSObjectType() != User.SObjectType
            && link.Visibility != 'AllUsers';
    }

    private static List<ContentDocumentLink> buildMissingLinks(
        Id contentDocumentId,
        Id threadId,
        Id networkId,
        Id opportunityId,
        AttachmentLinkState state
    ) {
        List<ContentDocumentLink> inserts = new List<ContentDocumentLink>();
        if (!state.hasThreadLink) inserts.add(buildAttachmentLink(contentDocumentId, threadId));
        if (networkId != null && !state.hasNetworkLink) inserts.add(buildAttachmentLink(contentDocumentId, networkId));
        if (opportunityId != null && !state.hasOpportunityLink) inserts.add(buildAttachmentLink(contentDocumentId, opportunityId));
        return inserts;
    }

    private static ContentDocumentLink buildAttachmentLink(Id contentDocumentId, Id linkedEntityId) {
        return new ContentDocumentLink(
            ContentDocumentId = contentDocumentId,
            LinkedEntityId    = linkedEntityId,
            ShareType         = 'V',
            Visibility        = 'AllUsers'
        );
    }

    /**
     * @description Trigger helper for ContentDocumentLink after insert/update.
     *              If the document is already used in CommunicatorMessage__c, normalize visibility.
     */
    public static void normalizeVisibilityForCommunicatorDocs(List<ContentDocumentLink> linksFromTrigger) {
        if (linksFromTrigger == null || linksFromTrigger.isEmpty()) return;

        Set<Id> docIds = new Set<Id>();
        for (ContentDocumentLink link : linksFromTrigger) {
            if (link.ContentDocumentId != null) {
                docIds.add(link.ContentDocumentId);
            }
        }
        if (docIds.isEmpty()) return;

        Set<String> docIdStrings = new Set<String>();
        for (Id docId : docIds) {
            docIdStrings.add(String.valueOf(docId));
        }

        Set<String> communicatorDocIds = new Set<String>();
        for (CommunicatorMessage__c msg : [
            SELECT ContentDocumentId__c
            FROM CommunicatorMessage__c
            WHERE HasAttachment__c = true
            AND ContentDocumentId__c IN :docIdStrings
            AND ContentDocumentId__c != null
        ]) {
            communicatorDocIds.add(msg.ContentDocumentId__c);
        }
        if (communicatorDocIds.isEmpty()) return;

        List<ContentDocumentLink> toUpdate = new List<ContentDocumentLink>();
        for (ContentDocumentLink link : linksFromTrigger) {
            if (link.Id == null || link.LinkedEntityId == null) continue;
            if (!communicatorDocIds.contains(String.valueOf(link.ContentDocumentId))) continue;
            if (link.LinkedEntityId.getSObjectType() == User.SObjectType) continue;
            if (link.Visibility == 'AllUsers') continue;

            toUpdate.add(new ContentDocumentLink(
                Id         = link.Id,
                Visibility = 'AllUsers',
                ShareType  = 'V'
            ));
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }
}