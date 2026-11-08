public with sharing class CommunicatorChatterBlockService {

    private static final String DEFAULT_BLOCK_MESSAGE =
        'O envio de novas mensagens via Chatter foi descontinuado para este processo. Utilize o Comunicador para novas interações relacionadas a este registro.';

    public static void validateFeedItems(List<FeedItem> newFeedItems) {
        if (newFeedItems == null || newFeedItems.isEmpty()) return;

        BlockSettings settings = getSettings();
        if (!settings.shouldBlock) return;

        for (FeedItem feedItemRecord : newFeedItems) {
            if (feedItemRecord == null || feedItemRecord.ParentId == null) continue;
            if (CommunicatorSystemEventService.isPublishingSystemEvents == true
                && feedItemRecord.ParentId.getSObjectType() == CommunicatorThread__c.SObjectType) {
                continue;
            }

            String objectApiName = getObjectApiName(feedItemRecord.ParentId);
            if (isBlockedObject(objectApiName, settings.blockedObjectApiNames)) {
                feedItemRecord.addError(settings.blockedMessage);
            }
        }
    }

    public static void validateFeedComments(List<FeedComment> newFeedComments) {
        if (newFeedComments == null || newFeedComments.isEmpty()) return;

        BlockSettings settings = getSettings();
        if (!settings.shouldBlock) return;

        Set<Id> feedItemIds = new Set<Id>();
        for (FeedComment feedCommentRecord : newFeedComments) {
            if (feedCommentRecord != null && feedCommentRecord.FeedItemId != null) {
                feedItemIds.add(feedCommentRecord.FeedItemId);
            }
        }
        if (feedItemIds.isEmpty()) return;

        Map<Id, FeedItem> feedItemById = new Map<Id, FeedItem>([
            SELECT Id, ParentId
            FROM FeedItem
            WHERE Id IN :feedItemIds
        ]);

        for (FeedComment feedCommentRecord : newFeedComments) {
            if (feedCommentRecord == null || feedCommentRecord.FeedItemId == null) continue;

            FeedItem parentFeedItem = feedItemById.get(feedCommentRecord.FeedItemId);
            if (parentFeedItem == null || parentFeedItem.ParentId == null) continue;

            String objectApiName = getObjectApiName(parentFeedItem.ParentId);
            if (isBlockedObject(objectApiName, settings.blockedObjectApiNames)) {
                feedCommentRecord.addError(settings.blockedMessage);
            }
        }
    }

    private static BlockSettings getSettings() {
        BlockSettings settings = new BlockSettings();
        settings.blockedMessage = getBlockedMessage();

        Boolean isEnabled = CommunicatorConfigService.getEnableChatterBlock();
        Set<String> blockedObjects = parseObjectApiNames(
            CommunicatorConfigService.getBlockedChatterObjectApiNames()
        );

        if (!isEnabled || blockedObjects.isEmpty()) {
            settings.shouldBlock = false;
            settings.blockedObjectApiNames = blockedObjects;
            return settings;
        }

        String bypassPermission = CommunicatorConfigService.getBypassChatterBlockPermission();
        Boolean hasBypass = String.isNotBlank(bypassPermission)
            && FeatureManagement.checkPermission(bypassPermission.trim());

        settings.shouldBlock = !hasBypass;
        settings.blockedObjectApiNames = blockedObjects;
        return settings;
    }

    private static String getBlockedMessage() {
        String message = CommunicatorConfigService.getChatterBlockedMessage();
        return String.isBlank(message) ? DEFAULT_BLOCK_MESSAGE : message;
    }

    private static Set<String> parseObjectApiNames(String rawValue) {
        Set<String> normalizedApiNames = new Set<String>();
        if (String.isBlank(rawValue)) return normalizedApiNames;

        for (String apiNamePart : rawValue.split(',')) {
            String apiName = apiNamePart == null ? null : apiNamePart.trim();
            if (String.isNotBlank(apiName)) {
                normalizedApiNames.add(apiName.toLowerCase());
            }
        }

        return normalizedApiNames;
    }

    private static Boolean isBlockedObject(String objectApiName, Set<String> blockedObjectApiNames) {
        if (String.isBlank(objectApiName) || blockedObjectApiNames == null || blockedObjectApiNames.isEmpty()) {
            return false;
        }

        return blockedObjectApiNames.contains(objectApiName.toLowerCase());
    }

    private static String getObjectApiName(Id recordId) {
        try {
            return recordId.getSObjectType().getDescribe().getName();
        } catch (Exception ex) {
            return null;
        }
    }

    private class BlockSettings {
        private Boolean shouldBlock = false;
        private String blockedMessage = DEFAULT_BLOCK_MESSAGE;
        private Set<String> blockedObjectApiNames = new Set<String>();
    }
}