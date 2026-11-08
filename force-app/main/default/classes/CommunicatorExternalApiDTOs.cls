public class CommunicatorExternalApiDTOs {

    public class ApiResponseDTO {
        public Boolean success;
        public Object data;
        public ErrorDTO error;
        public PageDTO page;
        public String timezone;
    }

    public class ErrorDTO {
        public String code;
        public String message;
        public String action;
        public String example;
        public List<String> details;
    }

    public class PageDTO {
        public Integer pageSize;
        public Integer currentPage;
        public Integer totalItems;
        public Integer totalPages;
        public Boolean hasMore;
        public String nextCursor;
    }

    public class QueryOptionsDTO {
        public Integer pageSize;
        public Integer pageNumber;
        public String cursor;
        public String sortBy;
        public String sortDirection;
    }

    public class UserContextDTO {
        public Id userId;
        public String userName;
        public Boolean isActive;
        public String userType;
        public String licenseName;
        public Id userRoleId;
        public String timezoneSidKey;
        public Set<Id> queueIds = new Set<Id>();
        public Set<Id> assessoriaIds = new Set<Id>();
        public Set<Id> conventionalGroupIds = new Set<Id>();
        public Set<Id> broadcastGroupIds = new Set<Id>();
        public Set<Id> participantThreadIds = new Set<Id>();
        public Set<Id> participantOpportunityIds = new Set<Id>();
        public Set<Id> accessibleOpportunityIds = new Set<Id>();
        public Set<Id> accessibleThreadIds = new Set<Id>();
        public Boolean isSalesforcePlatform;
        public Boolean isCoreSalesforce;
        public Boolean isPartnerCommunity;
    }

    public class RecordSearchItemDTO {
        public String recordId;
        public String recordName;
        public String recordObjectApiName;
        public String opportunityId;
        public String opportunityName;
        public String repasseId;
        public String repasseName;
        public String currentStage;
        public Boolean hasThread;
    }

    public class ConversationItemDTO {
        public String viewMode;
        public String threadId;
        public String threadName;
        public String currentThreadId;
        public String recordId;
        public String recordName;
        public String recordObjectApiName;
        public String opportunityId;
        public String opportunityName;
        public String repasseId;
        public String repasseName;
        public String currentStage;
        public String stage;
        public String lastMessageAt;
        public Integer unreadCount;
        public Boolean isRead;
        public String lastMessageBody;
        public String lastSenderId;
        public String lastSenderName;
        public Boolean hasThread;
        public Integer threadCount;
        public List<String> stages;
        public List<ConversationItemDTO> threads;
    }

    public class RecordThreadsDTO {
        public Boolean hasThread;
        public String status;
        public String message;
        public List<ConversationItemDTO> threads;
    }

    public class ChatThreadDTO {
        public String threadId;
        public String threadName;
        public String recordId;
        public String recordName;
        public String recordObjectApiName;
        public String opportunityId;
        public String opportunityName;
        public String repasseId;
        public String repasseName;
        public String currentStage;
        public String stage;
        public Integer unreadCount;
        public List<ParticipantDTO> participants;
        public List<MessageDTO> messages;
    }

    public class MessageDTO {
        public String messageId;
        public String threadId;
        public String threadName;
        public String stage;
        public String body;
        public String subject;
        public String status;
        public String sentAt;
        public String editedAt;
        public String senderId;
        public String senderName;
        public String senderPhotoUrl;
        public Boolean isSystemMessage;
        public Boolean hasMention;
        public Boolean hasAttachment;
        public List<IdNamePairDTO> mentionedUsers;
        public List<IdNamePairDTO> mentionedGroups;
        public List<AttachmentDTO> attachments;
    }

    public class AttachmentDTO {
        public String contentDocumentId;
        public String contentVersionId;
        public String fileName;
    }

    public class ParticipantDTO {
        public String participantId;
        public String userId;
        public String userName;
        public String photoUrl;
        public String role;
        public String lastReadAt;
    }

    public class SendMessageRequestDTO {
        public String userId;
        public String threadId;
        public String recordId;
        public String body;
        public String externalId;
        public List<String> mentionedUserIds;
        public List<String> mentionedGroupIds;
        public String contentDocumentId;
        public String contentVersionId;
    }

    public class SendGroupMessageRequestDTO {
        public String userId;
        public String groupId;
        public String body;
        public String externalId;
        public List<String> mentionedUserIds;
        public List<String> mentionedGroupIds;
        public String contentDocumentId;
        public String contentVersionId;
    }

    public class SetReadRequestDTO {
        public String userId;
        public String threadId;
        public String broadcastId;
        public String readAt;
    }

    public class NotificationItemDTO {
        public String notificationId;
        public String notificationName;
        public String messageId;
        public String messageName;
        public String threadId;
        public String threadName;
        public String recipientId;
        public String recipientName;
        public String recordId;
        public String recordName;
        public String type;
        public Boolean isRead;
        public String readState;
        public Boolean isRecent;
        public String sentAt;
        public String readAt;
    }

    public class UnreadCountDTO {
        public Integer totalUnreadCount;
        public Integer mentionUnreadCount;
        public Integer groupUnreadCount;
        public Integer broadcastUnreadCount;
        public Integer threadUnreadCount;
        public String threadId;
        public String recordId;
    }

    public class GroupCreateRequestDTO {
        public String userId;
        public String name;
        public String description;
        public List<String> memberUserIds;
    }

    public class GroupUsersRequestDTO {
        public String userId;
        public String groupId;
        public List<String> usersToAdd;
        public List<String> usersToRemove;
    }

    public class GroupItemDTO {
        public String groupId;
        public String groupName;
        public String description;
        public String type;
        public Integer memberCount;
        public Integer unreadCount;
        public String createdByUserId;
        public String createdByUserName;
        public String lastActivityAt;
        public String threadId;
    }

    public class GroupDetailDTO {
        public GroupItemDTO groupInfo;
        public List<ParticipantDTO> members;
        public ChatThreadDTO chat;
    }

    public class BroadcastCreateRequestDTO {
        public String userId;
        public String name;
        public String description;
        public List<BroadcastAudienceDTO> audiences;
    }

    public class BroadcastSendRequestDTO {
        public String userId;
        public String groupId;
        public String subject;
        public String body;
        public String externalId;
        public String contentDocumentId;
        public String contentVersionId;
    }

    public class BroadcastAudienceDTO {
        public String audienceType;
        public String targetId;
        public String targetName;
        public Integer sortOrder;
    }

    public class BroadcastItemDTO {
        public String broadcastId;
        public String broadcastName;
        public String description;
        public String threadId;
        public String createdByUserId;
        public String createdByUserName;
        public String sentAt;
        public String lastActivityAt;
        public Integer unreadCount;
        public Boolean canPublish;
    }

    public class BroadcastDetailDTO {
        public BroadcastItemDTO broadcast;
        public List<BroadcastAudienceDTO> audiences;
        public List<MessageDTO> messages;
    }

    public class IdNamePairDTO {
        public String id;
        public String name;
    }
}