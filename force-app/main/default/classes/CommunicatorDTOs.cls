/**
 * @description Wrapper class holding all Communicator DTOs as inner classes.
 *              Apex requires all top-level types in a file to share the same name as the file.
 *              DTOs are declared here as inner classes to avoid multiple top-level class files.
 */
public class CommunicatorDTOs {
    public class FollowStateDTO {
        @AuraEnabled public Boolean isFollowing = false;
        @AuraEnabled public Boolean isCreator = false;
        @AuraEnabled public Boolean canChange = false;
    }


    // ─────────────────────────────────────────
    // Integration — Outbound
    // ─────────────────────────────────────────

    public class MessageEventDTO {
        @AuraEnabled public String  threadExternalId;
        @AuraEnabled public String  threadId;
        @AuraEnabled public String  messageId;
        @AuraEnabled public String  message;
        @AuraEnabled public List<String> user_ids;
        @AuraEnabled public String  senderId;
        @AuraEnabled public String  senderName;
        @AuraEnabled public String  messageBody;
        @AuraEnabled public String  sentAt;
        @AuraEnabled public Boolean hasAttachment;
    }

    // ─────────────────────────────────────────
    // Integration — Inbound
    // ─────────────────────────────────────────

    public class ExternalHistoryDTO {
        public String                   threadId;
        public List<ExternalMessageDTO> messages;
        public Integer                  totalCount;
    }

    public class ExternalMessageDTO {
        public String  externalId;
        public String  body;
        public String  senderId;
        public String  senderName;
        public String  sentAt;
        public Boolean hasAttachment;
    }

    public class IntegrationResponseDTO {
        @AuraEnabled public Integer statusCode;
        @AuraEnabled public Boolean success;
        @AuraEnabled public String  rawBody;
    }

    public class SocketInboundResultDTO {
        @AuraEnabled public Boolean success;
        @AuraEnabled public Boolean created;
        @AuraEnabled public String  messageId;
        @AuraEnabled public String  status;
        @AuraEnabled public String  errorMessage;
    }

    public class AttachmentFileDTO {
        @AuraEnabled public String fileName;
        @AuraEnabled public String contentType;
        @AuraEnabled public String fileExtension;
        @AuraEnabled public String base64Data;
    }

    public class MessageAttachmentDTO {
        @AuraEnabled public String messageId;
        @AuraEnabled public String contentDocumentId;
        @AuraEnabled public String fileName;
        @AuraEnabled public String fileExtension;
    }

    // ─────────────────────────────────────────
    // Broadcast
    // ─────────────────────────────────────────

    public class BroadcastListItemDTO {
        @AuraEnabled public String groupId;
        @AuraEnabled public String groupName;
        @AuraEnabled public String description;
        @AuraEnabled public String createdByUserId;
        @AuraEnabled public String createdByUserName;
        @AuraEnabled public String createdByUserPhotoUrl;
        @AuraEnabled public String threadId;
        @AuraEnabled public Datetime broadcastLastActivityAt;
        @AuraEnabled public Datetime lastMessageAt;
        @AuraEnabled public Integer unreadCount;
        @AuraEnabled public Boolean canPublish;
    }

    public class BroadcastDetailsDTO {
        @AuraEnabled public BroadcastListItemDTO broadcast;
        @AuraEnabled public List<CommunicatorBroadcastAudience__c> audiences;
    }

    public class BroadcastListPageDTO {
        @AuraEnabled public List<BroadcastListItemDTO> items;
        @AuraEnabled public String nextCursor;
    }

    public class BroadcastAuthoringContextDTO {
        @AuraEnabled public Boolean canCreateBroadcast;
        @AuraEnabled public Integer maxUploadBroadcastFileSizeMB;
        @AuraEnabled public Decimal maxClipboardBroadcastImageSizeMB;
        @AuraEnabled public Boolean uploadConfigValid;
        @AuraEnabled public String uploadConfigErrorMessage;
    }

    public class BroadcastThreadDTO {
        @AuraEnabled public BroadcastListItemDTO broadcast;
        @AuraEnabled public CommunicatorThread__c thread;
    }

    public class BroadcastMessageDTO {
        @AuraEnabled public String Id;
        @AuraEnabled public String Name;
        @AuraEnabled public String subject;
        @AuraEnabled public String body;
        @AuraEnabled public String searchBody;
        @AuraEnabled public String status;
        @AuraEnabled public Boolean hasAttachment;
        @AuraEnabled public String contentDocumentId;
        @AuraEnabled public Datetime sentAt;
        @AuraEnabled public Datetime editedAt;
        @AuraEnabled public Datetime SystemModstamp;
        @AuraEnabled public Boolean isSystemMessage;
        @AuraEnabled public Boolean hasMention;
        @AuraEnabled public String senderId;
        @AuraEnabled public String senderName;
        @AuraEnabled public String senderPhotoUrl;
        @AuraEnabled public String threadId;
        @AuraEnabled public String broadcastDistributionJobId;
        @AuraEnabled public String broadcastDistributionError;
        @AuraEnabled public Datetime broadcastDistributionCompletedAt;
        @AuraEnabled public Boolean showEditAction;
        @AuraEnabled public Boolean canEdit;
        @AuraEnabled public Datetime editDeadline;
        @AuraEnabled public String editBlockedReason;
        @AuraEnabled public Boolean canRetry;
    }

    public class BroadcastPollPageDTO {
        @AuraEnabled public List<BroadcastMessageDTO> messages;
        @AuraEnabled public String nextCursor;
    }

    // ─────────────────────────────────────────
    // Record Search
    // ─────────────────────────────────────────

    /** Group of search results for one SObject type. */
    public class RecordResultDTO {
        @AuraEnabled public String              objectApiName;
        @AuraEnabled public String              objectLabel;
        @AuraEnabled public List<RecordItemDTO> records;
    }

    /** Single record result item. */
    public class RecordItemDTO {
        @AuraEnabled public String recordId;
        @AuraEnabled public String name;
        @AuraEnabled public String objectType;
    }

    /** Generic "Id + Name" reference used by LWC for related records. */
    public class IdNameDTO {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
    }

    /** Related records (AR / AB / Cotação) linked to one Opportunity. */
    public class OpportunityRelatedRefsDTO {
        @AuraEnabled public String arId;
        @AuraEnabled public String arName;
        @AuraEnabled public String analiseCreditoId;
        @AuraEnabled public String analiseCreditoName;
        @AuraEnabled public String abId;
        @AuraEnabled public String abName;
        @AuraEnabled public String quoteId;
        @AuraEnabled public String quoteName;
        @AuraEnabled public Integer quoteCount;
        @AuraEnabled public String resolvedRefType;
        @AuraEnabled public String resolvedRefId;
        @AuraEnabled public String resolvedRefName;
        @AuraEnabled public String resolvedRefObjectApiName;
    }

    /** Redirect decision when user clicks "Acessar oportunidade" in communicator. */
    public class OpportunityAccessRedirectDTO {
        @AuraEnabled public String action;
        @AuraEnabled public String recordId;
        @AuraEnabled public String objectApiName;
        @AuraEnabled public String message;
        @AuraEnabled public Boolean forceCommunityDetailUrl;
    }

    // ─────────────────────────────────────────
    // Mentions
    // ─────────────────────────────────────────

    /** A user or group that can be @mentioned in a message. */
    public class MentionCandidateDTO {
        @AuraEnabled public String  id;
        @AuraEnabled public String  name;
        @AuraEnabled public String  photoUrl;
        @AuraEnabled public String  candidateType; // 'User' or 'Group'
        @AuraEnabled public Integer memberCount;   // null for users
    }

    // ─────────────────────────────────────────
    // Configuration
    // ─────────────────────────────────────────

    /** Settings read from CommunicatorConfig__mdt, sent to LWC on init. */
    public class SettingsDTO {
        @AuraEnabled public List<String> objectApiNames;
        @AuraEnabled public Boolean      filterOpenOnly;
        @AuraEnabled public Integer      maxSearchResults;
        @AuraEnabled public Integer      maxRecentRecords;
        @AuraEnabled public Integer      pollingIntervalMs;
        @AuraEnabled public Integer      messagesPerPage;
        @AuraEnabled public Integer      threadsPerPage;
        @AuraEnabled public Boolean      hasGroupAccess;
        @AuraEnabled public Boolean      isSalesforcePlatformUser;
        @AuraEnabled public Boolean      hasCommunicatorChatPermission;
        @AuraEnabled public String       noPermissionMessage;
        @AuraEnabled public String       chatterHistoryEmptyMessage;
        @AuraEnabled public Integer      maxUploadFileSizeMB;
        @AuraEnabled public String       uploadFileSizeErrorMessage;
    }

    /** Result of server-side upload size validation. */
    public class UploadValidationResultDTO {
        @AuraEnabled public List<String> validContentDocumentIds;
        @AuraEnabled public List<String> rejectedFileNames;
        @AuraEnabled public String       errorMessage;
    }

    // ─────────────────────────────────────────
    // User Search (Group member picker)
    // ─────────────────────────────────────────

    /** Lightweight result used by the group-member search picker. */
    public class UserResultDTO {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
    }

    // ─────────────────────────────────────────
    // Groups Tab
    // ─────────────────────────────────────────

    /** One row in the groups tab list view. */
    public class GroupListItemDTO {
        @AuraEnabled public String  groupId;
        @AuraEnabled public String  groupName;
        @AuraEnabled public String  createdByUserId;         // Id of the user who created the group
        @AuraEnabled public String  lastMentionAt;           // ISO datetime string, or null
        @AuraEnabled public Integer unreadMentionCount;      // unread for current user
        @AuraEnabled public Integer activeOpportunityCount;  // distinct RecordId__c
    }

    /** One member row in the group details modal. */
    public class GroupMemberDTO {
        @AuraEnabled public String memberId;   // CommunicatorGroupMember__c.Id
        @AuraEnabled public String userId;     // User Id
        @AuraEnabled public String userName;   // User.Name
    }

    /** Result of getSourceThreadsInfo — tells the group timeline whether replies are allowed. */
    public class SourceThreadInfoDTO {
        @AuraEnabled public String  threadId;
        @AuraEnabled public String  stageName;
        @AuraEnabled public Boolean canReply;
        @AuraEnabled public String  opportunityId;
        @AuraEnabled public String  opportunityName;
        @AuraEnabled public String  arId;
        @AuraEnabled public String  arName;
        @AuraEnabled public String  abId;
        @AuraEnabled public String  abName;
        @AuraEnabled public String  quoteId;
        @AuraEnabled public String  quoteName;
        @AuraEnabled public String  resolvedRefType;
        @AuraEnabled public String  resolvedRefId;
        @AuraEnabled public String  resolvedRefName;
        @AuraEnabled public String  resolvedRefObjectApiName;
    }

    // ─────────────────────────────────────────
    // Thread History List
    // ─────────────────────────────────────────

    /** One row in the thread history list view. */
    public class ThreadListItemDTO {
        @AuraEnabled public String  threadId;
        @AuraEnabled public String  threadName;
        @AuraEnabled public String  recordId;
        @AuraEnabled public String  recordName;
        @AuraEnabled public String  recordType;
        @AuraEnabled public Boolean hasRepasse;
        @AuraEnabled public String  stageName;     // stage when the thread was created
        @AuraEnabled public String  currentStage;  // live current stage of the linked record
        @AuraEnabled public String  displayStatus;
        @AuraEnabled public String  rawRepasseStatus;
        @AuraEnabled public String  displayStatusLabel;
        @AuraEnabled public String  lastMessageAt;
        @AuraEnabled public String  lastReadAt;
        @AuraEnabled public Integer unreadCount;
        @AuraEnabled public Boolean isRead;
        @AuraEnabled public String  statusLabel;
        @AuraEnabled public String  lastSenderId;
        @AuraEnabled public String  lastMessageBody;
        @AuraEnabled public String  lastSenderName;
        @AuraEnabled public String  lastSenderPhoto;
        @AuraEnabled public Boolean lastIsSystemMessage;
        @AuraEnabled public String  repasseName;
        @AuraEnabled public String  repasseOpportunityId;
    }

    public class ThreadPresenceOverrideDTO {
        @AuraEnabled public String threadId;
        @AuraEnabled public String userId;
        @AuraEnabled public String status;
    }

    public class NotificationNavigationDTO {
        @AuraEnabled public String threadId;
        @AuraEnabled public String recordId;
        @AuraEnabled public String messageId;
    }

    public class MessagePollPageDTO {
        @AuraEnabled public List<CommunicatorMessage__c> messages;
        @AuraEnabled public String nextCursor;
        @AuraEnabled public Boolean hasMore;
    }

    public class MessagePollCursorDTO {
        @AuraEnabled public Datetime timestamp;
        @AuraEnabled public String source;
        @AuraEnabled public String itemId;
    }
}