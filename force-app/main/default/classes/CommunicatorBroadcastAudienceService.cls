/**
 * @description Dynamic audience resolver and authorization source for Broadcast groups.
 *              Broadcast access never depends on participants, group members or recipient shares.
 */
public without sharing class CommunicatorBroadcastAudienceService {

    public enum UserAudienceCategory {
        CORE_SALESFORCE,
        CORE_PLATFORM,
        COMMUNITY_PARTNER,
        UNSUPPORTED
    }

    private static final String GROUP_TYPE_BROADCAST = 'Broadcast';
    private static final String TYPE_ROLE = 'Role';
    private static final String TYPE_ROLE_INTERNAL = 'RoleAndSubordinatesInternal';
    private static final String TYPE_ROLE_PORTAL = 'RoleAndSubordinatesPortal';
    private static final String TYPE_ROLE_INTERNAL_PORTAL = 'RoleAndSubordinatesInternalAndPortal';
    private static final String TYPE_PUBLIC_GROUP = 'PublicGroup';
    private static final String TYPE_DIRECT_USER = 'DirectUser';
    private static final String TYPE_SALES_COMPANY = 'SalesCompany';
    private static final String TYPE_JOB_TITLE = 'JobTitle';
    private static final String TYPE_JOB_TITLE_AND_SUBORDINATES = 'JobTitleAndSubordinates';
    private static final String TYPE_ALL_SUPPORTED_USERS = 'AllSupportedUsers';
    private static final String ALL_SUPPORTED_USERS_TARGET_NAME = 'Todos os usuarios';
    private static final String MODE_ALL = 'ALL';
    private static final String MODE_INTERNAL = 'INTERNAL';
    private static final String MODE_PORTAL = 'PORTAL';
    private static final String MODE_EXACT = 'EXACT';
    private static final String DML_INSERT = 'INSERT';
    private static final String DML_UPDATE = 'UPDATE';
    private static final String DML_DELETE = 'DELETE';
    private static final String GROUP_OBJECT = 'CommunicatorGroup__c';
    private static final String AUDIENCE_OBJECT = 'CommunicatorBroadcastAudience__c';
    private static final Integer MAX_PUBLIC_GROUP_MEMBERS = 10000;
    private static final Integer MAX_PUBLIC_GROUP_DEPTH = 20;
    private static final Integer PUBLIC_GROUP_QUERY_RESERVE = 8;
    private static final Integer PUBLIC_GROUP_ROW_RESERVE = 1000;
    private static final Integer PUBLIC_GROUP_CPU_RESERVE_MS = 2000;
    private static final Integer PUBLIC_GROUP_HEAP_RESERVE_BYTES = 400000;
    private static final Integer PUBLISH_JOB_TITLE_SUBTREE_QUERY_RESERVE = 12;
    private static final Integer PUBLISH_JOB_TITLE_SUBTREE_ROW_RESERVE = 10000;
    private static final Integer PUBLISH_JOB_TITLE_SUBTREE_CPU_RESERVE_MS = 2500;
    private static final Integer PUBLISH_JOB_TITLE_SUBTREE_HEAP_RESERVE_BYTES = 500000;
    private static final Integer PUBLISH_JOB_TITLE_SUBTREE_MAX_VISITED_CONTACTS = 4000;
    private static final Integer PUBLISH_JOB_TITLE_SUBTREE_MAX_FRONTIER_CONTACTS = 1000;
    private static final Integer AUTH_JOB_TITLE_SUBTREE_QUERY_RESERVE = 2;
    private static final Integer AUTH_JOB_TITLE_SUBTREE_ROW_RESERVE = 500;
    private static final Integer AUTH_JOB_TITLE_SUBTREE_CPU_RESERVE_MS = 500;
    private static final Integer AUTH_JOB_TITLE_SUBTREE_HEAP_RESERVE_BYTES = 150000;
    private static final Integer AUTH_JOB_TITLE_SUBTREE_MAX_VISITED_CONTACTS = 200;
    private static final Integer AUTH_JOB_TITLE_SUBTREE_MAX_FRONTIER_CONTACTS = 50;
    private static final Integer AUTH_JOB_TITLE_INITIAL_CONTACT_MAX_CONTACTS = 50;
    private static final String JOB_TITLE_AUTH_LIMIT_MESSAGE =
        'Não foi possível validar o acesso do usuário para a audiência de cargo dentro do limite seguro.';
    private static final String JOB_TITLE_AND_SUBORDINATES_LIMIT_MESSAGE =
        'A audiencia "Cargo e subordinados" excedeu o limite sincrono suportado para esta operacao.';
    private static final String PUBLIC_GROUP_LIMIT_MESSAGE =
        'A expansao de grupos publicos excedeu o limite seguro.';
    private static final String PUBLIC_GROUP_INVALID_MESSAGE =
        'O grupo publico selecionado nao e valido.';
    private static final String PUBLIC_GROUP_UNSUPPORTED_MEMBER_MESSAGE_PREFIX =
        'O grupo publico selecionado contem um tipo de membro nao suportado: ';
    private static final String PUBLIC_GROUP_UNSUPPORTED_MEMBER_MESSAGE_SUFFIX =
        '. Revise a composicao do grupo antes de publicar.';
    private static final String PUBLIC_GROUP_INVALID_ROLE_MEMBER_MESSAGE =
        'O grupo publico selecionado contem uma regra de papel invalida. Revise a composicao do grupo antes de publicar.';
    private static final String EMPTY_AUDIENCE_MESSAGE =
        'Não é possível enviar o comunicado porque não existem destinatários válidos no momento. Revise o público selecionado.';

    private static final String BROADCAST_NAME_REQUIRED_MESSAGE = 'Informe o nome do comunicado.';

    @TestVisible private static Boolean forceCreatorPermissionForTest;
    @TestVisible private static AudienceDataProvider dataProvider = new SoqlAudienceDataProvider();
    @TestVisible private static Integer publishJobTitleSubtreeQueryReserveOverride;
    @TestVisible private static Integer publishJobTitleSubtreeRowReserveOverride;
    @TestVisible private static Integer publishJobTitleSubtreeMaxVisitedContactsOverride;
    @TestVisible private static Integer publishJobTitleSubtreeMaxFrontierContactsOverride;
    @TestVisible private static Integer authorizationJobTitleSubtreeQueryReserveOverride;
    @TestVisible private static Integer authorizationJobTitleSubtreeMaxVisitedContactsOverride;
    @TestVisible private static Integer authorizationJobTitleSubtreeMaxFrontierContactsOverride;
    private static DmlAuthorization pendingDmlAuthorization;

    private class DmlAuthorization {
        private String objectApiName;
        private String operation;
        private Integer expectedCount;
        private List<String> expectedSignatures;

        private DmlAuthorization(
            String objectApiName,
            String operation,
            List<String> expectedSignatures
        ) {
            this.objectApiName = objectApiName;
            this.operation = operation;
            this.expectedCount = expectedSignatures.size();
            this.expectedSignatures = expectedSignatures;
        }
    }

    public class AudienceUserRecord {
        public Id userId;
        public Boolean isActive;
        public String userType;
        public String licenseName;
        public Id userRoleId;
        public String salesCompany;
        public Id contactId;
        public Id contactJobTitleId;

        public AudienceUserRecord(
            Id userId,
            Boolean isActive,
            String userType,
            String licenseName,
            Id userRoleId
        ) {
            this(userId, isActive, userType, licenseName, userRoleId, null, null, null);
        }

        public AudienceUserRecord(
            Id userId,
            Boolean isActive,
            String userType,
            String licenseName,
            Id userRoleId,
            String salesCompany,
            Id contactId,
            Id contactJobTitleId
        ) {
            this.userId = userId;
            this.isActive = isActive;
            this.userType = userType;
            this.licenseName = licenseName;
            this.userRoleId = userRoleId;
            this.salesCompany = salesCompany;
            this.contactId = contactId;
            this.contactJobTitleId = contactJobTitleId;
        }
    }

    public class AudienceContactRecord {
        public Id contactId;
        public Id reportsToId;
        public Id cargoId;
        public Id usuarioId;
        public Boolean usuarioIsActive;
        public String usuarioType;
        public Id usuarioRoleId;
        public String usuarioLicenseName;
        public String usuarioSalesCompany;

        public AudienceContactRecord(
            Id contactId,
            Id reportsToId,
            Id cargoId,
            Id usuarioId,
            Boolean usuarioIsActive,
            String usuarioType,
            Id usuarioRoleId,
            String usuarioLicenseName,
            String usuarioSalesCompany
        ) {
            this.contactId = contactId;
            this.reportsToId = reportsToId;
            this.cargoId = cargoId;
            this.usuarioId = usuarioId;
            this.usuarioIsActive = usuarioIsActive;
            this.usuarioType = usuarioType;
            this.usuarioRoleId = usuarioRoleId;
            this.usuarioLicenseName = usuarioLicenseName;
            this.usuarioSalesCompany = usuarioSalesCompany;
        }
    }

    public class AudiencePicklistOptionRecord {
        public String value;
        public String label;
        public Boolean isActive;

        public AudiencePicklistOptionRecord(String value, String label, Boolean isActive) {
            this.value = value;
            this.label = label;
            this.isActive = isActive;
        }
    }

    public class JobTitleRecord {
        public Id jobTitleId;
        public String name;

        public JobTitleRecord(Id jobTitleId, String name) {
            this.jobTitleId = jobTitleId;
            this.name = name;
        }
    }

    public class AudienceGroupRecord {
        public Id groupId;
        public String groupType;
        public Id relatedId;

        public AudienceGroupRecord(Id groupId, String groupType, Id relatedId) {
            this.groupId = groupId;
            this.groupType = groupType;
            this.relatedId = relatedId;
        }
    }

    public class AudienceGroupMemberRecord {
        public Id groupId;
        public Id memberId;

        public AudienceGroupMemberRecord(Id groupId, Id memberId) {
            this.groupId = groupId;
            this.memberId = memberId;
        }
    }

    public interface AudienceDataProvider {
        List<AudienceUserRecord> getUsersByIds(Set<Id> userIds);
        List<AudienceUserRecord> getActiveUsersByRoleIds(Set<Id> roleIds);
        List<AudienceUserRecord> getActiveUsersBySalesCompanies(Set<String> salesCompanies);
        List<AudienceContactRecord> getActiveUserContactsByJobTitleIds(Set<Id> jobTitleIds, Integer limitSize);
        List<AudienceContactRecord> getActiveUserContactsByIds(Set<Id> contactIds, Integer limitSize);
        List<AudienceContactRecord> getContactsByUserId(Id userId, Integer limitSize);
        List<AudienceContactRecord> getContactsByIds(Set<Id> contactIds);
        List<AudienceContactRecord> getContactsByJobTitleIds(Set<Id> jobTitleIds, Integer limitSize);
        List<AudienceContactRecord> getChildContactsByManagerIds(Set<Id> managerContactIds, Integer limitSize);
        List<AudienceGroupRecord> getGroupsByIds(Set<Id> groupIds);
        List<AudienceGroupMemberRecord> getGroupMembersByGroupIds(Set<Id> groupIds, Integer limitSize);
        Set<Id> getExistingRoleIds(Set<Id> roleIds);
        Map<Id, Set<Id>> getRoleAndDescendantIdsByRoot(Set<Id> rootRoleIds);
        List<CommunicatorGroup__c> getCommunicatorGroups(Set<Id> groupIds);
        List<CommunicatorBroadcastAudience__c> getActiveCriteria(Set<Id> groupIds);
        List<AudiencePicklistOptionRecord> getSalesCompanyPicklistOptions();
        List<JobTitleRecord> getJobTitlesByIds(Set<Id> jobTitleIds);
        List<JobTitleRecord> searchJobTitles(String keyword, Integer limitSize);
    }

    private class SoqlAudienceDataProvider implements AudienceDataProvider {
        public List<AudienceUserRecord> getUsersByIds(Set<Id> userIds) {
            List<AudienceUserRecord> result = new List<AudienceUserRecord>();
            if (userIds == null || userIds.isEmpty()) return result;
            for (User userRecord : [
                SELECT Id, IsActive, UserType, UserRoleId, EmpresaVendas__c,
                       ContactId, Contact.Cargo__c, Profile.UserLicense.Name
                FROM User
                WHERE Id IN :userIds
            ]) {
                result.add(toAudienceUser(userRecord));
            }
            return result;
        }

        public List<AudienceUserRecord> getActiveUsersByRoleIds(Set<Id> roleIds) {
            List<AudienceUserRecord> result = new List<AudienceUserRecord>();
            if (roleIds == null || roleIds.isEmpty()) return result;
            for (User userRecord : [
                SELECT Id, IsActive, UserType, UserRoleId, EmpresaVendas__c,
                       ContactId, Contact.Cargo__c, Profile.UserLicense.Name
                FROM User
                WHERE IsActive = true
                AND UserRoleId IN :roleIds
            ]) {
                result.add(toAudienceUser(userRecord));
            }
            return result;
        }

        public List<AudienceUserRecord> getActiveUsersBySalesCompanies(Set<String> salesCompanies) {
            List<AudienceUserRecord> result = new List<AudienceUserRecord>();
            if (salesCompanies == null || salesCompanies.isEmpty()) return result;
            for (User userRecord : [
                SELECT Id, IsActive, UserType, UserRoleId, EmpresaVendas__c,
                       ContactId, Contact.Cargo__c, Profile.UserLicense.Name
                FROM User
                WHERE IsActive = true
                AND EmpresaVendas__c IN :salesCompanies
            ]) {
                result.add(toAudienceUser(userRecord));
            }
            return result;
        }

        public List<AudienceContactRecord> getActiveUserContactsByJobTitleIds(
            Set<Id> jobTitleIds,
            Integer limitSize
        ) {
            List<AudienceContactRecord> result = new List<AudienceContactRecord>();
            if (jobTitleIds == null || jobTitleIds.isEmpty()) return result;
            for (Contact contactRecord : [
                SELECT Id, ReportsToId, Cargo__c, Usuario__c, Usuario__r.IsActive,
                       Usuario__r.UserType, Usuario__r.UserRoleId,
                       Usuario__r.EmpresaVendas__c, Usuario__r.Profile.UserLicense.Name
                FROM Contact
                WHERE Cargo__c IN :jobTitleIds
                AND Usuario__c != null
                AND Usuario__r.IsActive = true
            ]) {
                result.add(new AudienceContactRecord(
                    contactRecord.Id,
                    contactRecord.ReportsToId,
                    contactRecord.Cargo__c,
                    contactRecord.Usuario__c,
                    contactRecord.Usuario__r != null ? contactRecord.Usuario__r.IsActive : null,
                    contactRecord.Usuario__r != null ? contactRecord.Usuario__r.UserType : null,
                    contactRecord.Usuario__r != null ? contactRecord.Usuario__r.UserRoleId : null,
                    contactRecord.Usuario__r != null &&
                        contactRecord.Usuario__r.Profile != null &&
                        contactRecord.Usuario__r.Profile.UserLicense != null
                        ? contactRecord.Usuario__r.Profile.UserLicense.Name
                        : null,
                    contactRecord.Usuario__r != null ? contactRecord.Usuario__r.EmpresaVendas__c : null
                ));
            }
            return result;
        }

        public List<AudienceContactRecord> getActiveUserContactsByIds(Set<Id> contactIds, Integer limitSize) {
            List<AudienceContactRecord> result = new List<AudienceContactRecord>();
            if (contactIds == null || contactIds.isEmpty()) return result;
            Integer validatedLimitSize = requirePositiveQueryLimit(limitSize);
            for (Contact contactRecord : [
                SELECT Id, ReportsToId, Cargo__c, Usuario__c, Usuario__r.IsActive,
                       Usuario__r.UserType, Usuario__r.UserRoleId,
                       Usuario__r.EmpresaVendas__c, Usuario__r.Profile.UserLicense.Name
                FROM Contact
                WHERE Id IN :contactIds
                AND Usuario__c != null
                AND Usuario__r.IsActive = true
                LIMIT :validatedLimitSize
            ]) {
                result.add(new AudienceContactRecord(
                    contactRecord.Id,
                    contactRecord.ReportsToId,
                    contactRecord.Cargo__c,
                    contactRecord.Usuario__c,
                    contactRecord.Usuario__r != null ? contactRecord.Usuario__r.IsActive : null,
                    contactRecord.Usuario__r != null ? contactRecord.Usuario__r.UserType : null,
                    contactRecord.Usuario__r != null ? contactRecord.Usuario__r.UserRoleId : null,
                    contactRecord.Usuario__r != null &&
                        contactRecord.Usuario__r.Profile != null &&
                        contactRecord.Usuario__r.Profile.UserLicense != null
                        ? contactRecord.Usuario__r.Profile.UserLicense.Name
                        : null,
                    contactRecord.Usuario__r != null ? contactRecord.Usuario__r.EmpresaVendas__c : null
                ));
            }
            return result;
        }

        public List<AudienceContactRecord> getContactsByUserId(Id userId, Integer limitSize) {
            List<AudienceContactRecord> result = new List<AudienceContactRecord>();
            if (userId == null) return result;
            Integer validatedLimitSize = requirePositiveQueryLimit(limitSize);
            for (Contact contactRecord : [
                SELECT Id, ReportsToId, Cargo__c
                FROM Contact
                WHERE Usuario__c = :userId
                LIMIT :validatedLimitSize
            ]) {
                result.add(new AudienceContactRecord(
                    contactRecord.Id,
                    contactRecord.ReportsToId,
                    contactRecord.Cargo__c,
                    null,
                    null,
                    null,
                    null,
                    null,
                    null
                ));
            }
            return result;
        }

        public List<AudienceContactRecord> getContactsByIds(Set<Id> contactIds) {
            List<AudienceContactRecord> result = new List<AudienceContactRecord>();
            if (contactIds == null || contactIds.isEmpty()) return result;
            for (Contact contactRecord : [
                SELECT Id, ReportsToId, Cargo__c
                FROM Contact
                WHERE Id IN :contactIds
            ]) {
                result.add(new AudienceContactRecord(
                    contactRecord.Id,
                    contactRecord.ReportsToId,
                    contactRecord.Cargo__c,
                    null,
                    null,
                    null,
                    null,
                    null,
                    null
                ));
            }
            return result;
        }

        public List<AudienceContactRecord> getContactsByJobTitleIds(Set<Id> jobTitleIds, Integer limitSize) {
            List<AudienceContactRecord> result = new List<AudienceContactRecord>();
            if (jobTitleIds == null || jobTitleIds.isEmpty()) return result;
            Integer validatedLimitSize = requirePositiveQueryLimit(limitSize);
            for (Contact contactRecord : [
                SELECT Id, ReportsToId, Cargo__c
                FROM Contact
                WHERE Cargo__c IN :jobTitleIds
                LIMIT :validatedLimitSize
            ]) {
                result.add(new AudienceContactRecord(
                    contactRecord.Id,
                    contactRecord.ReportsToId,
                    contactRecord.Cargo__c,
                    null,
                    null,
                    null,
                    null,
                    null,
                    null
                ));
            }
            return result;
        }

        public List<AudienceContactRecord> getChildContactsByManagerIds(
            Set<Id> managerContactIds,
            Integer limitSize
        ) {
            List<AudienceContactRecord> result = new List<AudienceContactRecord>();
            if (managerContactIds == null || managerContactIds.isEmpty()) return result;
            Integer validatedLimitSize = requirePositiveQueryLimit(limitSize);
            for (Contact contactRecord : [
                SELECT Id, ReportsToId, Cargo__c
                FROM Contact
                WHERE ReportsToId IN :managerContactIds
                LIMIT :validatedLimitSize
            ]) {
                result.add(new AudienceContactRecord(
                    contactRecord.Id,
                    contactRecord.ReportsToId,
                    contactRecord.Cargo__c,
                    null,
                    null,
                    null,
                    null,
                    null,
                    null
                ));
            }
            return result;
        }

        public List<AudienceGroupRecord> getGroupsByIds(Set<Id> groupIds) {
            List<AudienceGroupRecord> result = new List<AudienceGroupRecord>();
            if (groupIds == null || groupIds.isEmpty()) return result;
            for (Group groupRecord : [
                SELECT Id, Type, RelatedId
                FROM Group
                WHERE Id IN :groupIds
            ]) {
                result.add(new AudienceGroupRecord(groupRecord.Id, groupRecord.Type, groupRecord.RelatedId));
            }
            return result;
        }

        public List<AudienceGroupMemberRecord> getGroupMembersByGroupIds(Set<Id> groupIds, Integer limitSize) {
            List<AudienceGroupMemberRecord> result = new List<AudienceGroupMemberRecord>();
            if (groupIds == null || groupIds.isEmpty()) return result;
            Integer validatedLimitSize = requirePositiveQueryLimit(limitSize);
            for (GroupMember memberRecord : [
                SELECT GroupId, UserOrGroupId
                FROM GroupMember
                WHERE GroupId IN :groupIds
                LIMIT :validatedLimitSize
            ]) {
                result.add(new AudienceGroupMemberRecord(memberRecord.GroupId, memberRecord.UserOrGroupId));
            }
            return result;
        }

        public Set<Id> getExistingRoleIds(Set<Id> roleIds) {
            Set<Id> existingRoleIds = new Set<Id>();
            if (roleIds == null || roleIds.isEmpty()) return existingRoleIds;
            for (UserRole roleRecord : [
                SELECT Id
                FROM UserRole
                WHERE Id IN :roleIds
            ]) {
                existingRoleIds.add(roleRecord.Id);
            }
            return existingRoleIds;
        }

        public Map<Id, Set<Id>> getRoleAndDescendantIdsByRoot(Set<Id> rootRoleIds) {
            return CommunicatorRoleHierarchyService.getRoleAndDescendantIdsByRoot(rootRoleIds);
        }

        public List<CommunicatorGroup__c> getCommunicatorGroups(Set<Id> groupIds) {
            if (groupIds == null || groupIds.isEmpty()) return new List<CommunicatorGroup__c>();
            return [
                SELECT Id, Name, Type__c, IsActive__c, CreatedByUser__c, BroadcastLastActivityAt__c
                FROM CommunicatorGroup__c
                WHERE Id IN :groupIds
            ];
        }

        public List<CommunicatorBroadcastAudience__c> getActiveCriteria(Set<Id> groupIds) {
            if (groupIds == null || groupIds.isEmpty()) {
                return new List<CommunicatorBroadcastAudience__c>();
            }
            return [
                SELECT Id, CommunicatorGroup__c, AudienceType__c, TargetId__c,
                       TargetName__c, SortOrder__c, IsActive__c, AudienceKey__c
                FROM CommunicatorBroadcastAudience__c
                WHERE CommunicatorGroup__c IN :groupIds
                AND IsActive__c = true
                ORDER BY SortOrder__c ASC NULLS LAST, CreatedDate ASC
            ];
        }

        public List<AudiencePicklistOptionRecord> getSalesCompanyPicklistOptions() {
            List<AudiencePicklistOptionRecord> result = new List<AudiencePicklistOptionRecord>();
            for (Schema.PicklistEntry entry : User.EmpresaVendas__c.getDescribe().getPicklistValues()) {
                result.add(new AudiencePicklistOptionRecord(
                    entry.getValue(),
                    entry.getLabel(),
                    entry.isActive()
                ));
            }
            return result;
        }

        public List<JobTitleRecord> getJobTitlesByIds(Set<Id> jobTitleIds) {
            List<JobTitleRecord> result = new List<JobTitleRecord>();
            if (jobTitleIds == null || jobTitleIds.isEmpty()) return result;
            for (CargosDepartamentos__c jobTitle : [
                SELECT Id, Name
                FROM CargosDepartamentos__c
                WHERE Id IN :jobTitleIds
            ]) {
                result.add(new JobTitleRecord(jobTitle.Id, jobTitle.Name));
            }
            return result;
        }

        public List<JobTitleRecord> searchJobTitles(String keyword, Integer limitSize) {
            List<JobTitleRecord> result = new List<JobTitleRecord>();
            String term = normalizeSearchTerm(keyword);
            if (term.length() < 2) return result;

            String likeTerm = '%' + term.replaceAll('\\s+', '%') + '%';
            for (CargosDepartamentos__c jobTitle : [
                SELECT Id, Name
                FROM CargosDepartamentos__c
                WHERE Name LIKE :likeTerm
                ORDER BY Name
                LIMIT :limitSize
            ]) {
                result.add(new JobTitleRecord(jobTitle.Id, jobTitle.Name));
            }
            return result;
        }

        private AudienceUserRecord toAudienceUser(User userRecord) {
            String licenseName = userRecord.Profile != null && userRecord.Profile.UserLicense != null
                ? userRecord.Profile.UserLicense.Name
                : null;
            return new AudienceUserRecord(
                userRecord.Id,
                userRecord.IsActive,
                userRecord.UserType,
                licenseName,
                userRecord.UserRoleId,
                userRecord.EmpresaVendas__c,
                userRecord.ContactId,
                userRecord.Contact != null ? userRecord.Contact.Cargo__c : null
            );
        }

    }

    private class AudienceValidationContext {
        public Set<String> allowedPersistedInactiveSalesCompanies = new Set<String>();
        public Set<Id> existingDirectUserIds = new Set<Id>();
        public Set<Id> existingRoleIds = new Set<Id>();
        public Map<Id, AudienceGroupRecord> groupsById = new Map<Id, AudienceGroupRecord>();
        public Map<Id, JobTitleRecord> jobTitlesById = new Map<Id, JobTitleRecord>();
    }

    private class ValidatedAudienceTarget {
        public String audienceType;
        public Id idValue;
        public String textValue;
        public String targetName;

        public ValidatedAudienceTarget(
            String audienceType,
            Id idValue,
            String textValue,
            String targetName
        ) {
            this.audienceType = audienceType;
            this.idValue = idValue;
            this.textValue = textValue;
            this.targetName = targetName;
        }

        public String getCanonicalTargetId() {
            return idValue != null ? String.valueOf(idValue) : textValue;
        }
    }

    private class RoleRule {
        Id rootRoleId;
        String mode;
        Set<String> audienceKeys = new Set<String>();
        Boolean requireResolvedRoot = false;

        RoleRule(Id rootRoleId, String mode, Set<String> audienceKeys) {
            this(rootRoleId, mode, audienceKeys, false);
        }

        RoleRule(Id rootRoleId, String mode, Set<String> audienceKeys, Boolean requireResolvedRoot) {
            this.rootRoleId = rootRoleId;
            this.mode = mode;
            this.audienceKeys.addAll(audienceKeys);
            this.requireResolvedRoot = requireResolvedRoot == true;
        }
    }

    private class PublicGroupGraph {
        Map<Id, List<Id>> memberIdsByGroup = new Map<Id, List<Id>>();
        Map<Id, AudienceGroupRecord> groupsById = new Map<Id, AudienceGroupRecord>();
    }

    public static Map<Id, UserAudienceCategory> classifyUsers(Set<Id> userIds) {
        Map<Id, UserAudienceCategory> result = new Map<Id, UserAudienceCategory>();
        if (userIds == null || userIds.isEmpty()) return result;
        for (AudienceUserRecord userRecord : dataProvider.getUsersByIds(userIds)) {
            result.put(userRecord.userId, classifyUser(userRecord));
        }
        return result;
    }

    public static List<AudienceGroupRecord> getAsyncAudienceGroupsByIds(Set<Id> groupIds) {
        return dataProvider.getGroupsByIds(groupIds);
    }

    public static Map<Id, Set<Id>> getAsyncRoleAndDescendantIdsByRoot(Set<Id> rootRoleIds) {
        return dataProvider.getRoleAndDescendantIdsByRoot(rootRoleIds);
    }

    public static List<AudienceUserRecord> getAsyncActiveUsersByRoleIds(Set<Id> roleIds) {
        return dataProvider.getActiveUsersByRoleIds(roleIds);
    }

    public static List<AudienceContactRecord> getAsyncActiveUserContactsByIds(
        Set<Id> contactIds,
        Integer limitSize
    ) {
        return dataProvider.getActiveUserContactsByIds(contactIds, limitSize);
    }

    public static Set<Id> resolveRecipientUserIds(Set<Id> broadcastGroupIds) {
        Set<Id> result = new Set<Id>();
        for (Set<Id> recipientIds : resolveRecipientUserIdsByGroup(broadcastGroupIds).values()) {
            result.addAll(recipientIds);
        }
        return result;
    }

    public static Map<Id, Set<Id>> resolveRecipientUserIdsByGroup(Set<Id> broadcastGroupIds) {
        Set<Id> validGroupIds = getValidBroadcastGroupIds(broadcastGroupIds, false);
        Map<Id, Set<Id>> result = new Map<Id, Set<Id>>();
        for (Id groupId : validGroupIds) result.put(groupId, new Set<Id>());
        if (validGroupIds.isEmpty()) return result;

        Map<String, Set<Id>> resolvedByKey = resolveCriteria(
            dataProvider.getActiveCriteria(validGroupIds),
            false
        );
        for (Id groupId : validGroupIds) {
            Set<Id> recipients = resolvedByKey.get(String.valueOf(groupId));
            if (recipients != null) result.get(groupId).addAll(recipients);
        }
        return result;
    }

    public static Boolean canCurrentUserAccessBroadcast(Id broadcastGroupId) {
        if (broadcastGroupId == null) return false;
        Map<Id, Boolean> accessByGroup = getCurrentUserAccessByBroadcastGroup(
            new Set<Id>{ broadcastGroupId }
        );
        return accessByGroup.get(broadcastGroupId) == true;
    }

    public static Map<Id, Boolean> getCurrentUserAccessByBroadcastGroup(Set<Id> broadcastGroupIds) {
        Map<Id, Boolean> result = new Map<Id, Boolean>();
        if (broadcastGroupIds == null || broadcastGroupIds.isEmpty()) return result;
        for (Id groupId : broadcastGroupIds) result.put(groupId, false);

        Map<Id, CommunicatorGroup__c> groupsById = new Map<Id, CommunicatorGroup__c>();
        Set<Id> validGroupIds = new Set<Id>();
        for (CommunicatorGroup__c groupRecord : dataProvider.getCommunicatorGroups(broadcastGroupIds)) {
            if (groupRecord.Type__c != GROUP_TYPE_BROADCAST || groupRecord.IsActive__c != true) continue;
            groupsById.put(groupRecord.Id, groupRecord);
            validGroupIds.add(groupRecord.Id);
            if (groupRecord.CreatedByUser__c == UserInfo.getUserId()) result.put(groupRecord.Id, true);
        }
        if (validGroupIds.isEmpty()) return result;

        List<AudienceUserRecord> currentUsers = dataProvider.getUsersByIds(new Set<Id>{ UserInfo.getUserId() });
        if (currentUsers.isEmpty()) return result;
        AudienceUserRecord currentUser = currentUsers[0];
        if (!isSupportedActiveUser(currentUser)) return result;

        List<CommunicatorBroadcastAudience__c> criteria = dataProvider.getActiveCriteria(validGroupIds);
        Set<Id> publicRootIds = new Set<Id>();
        Set<Id> hierarchyRootIds = new Set<Id>();
        Boolean hasJobTitleCriterion = false;
        Boolean hasJobTitleAndSubordinatesCriterion = false;
        for (CommunicatorBroadcastAudience__c criterion : criteria) {
            ValidatedAudienceTarget target = validateCriterionStructure(
                criterion,
                false,
                new AudienceValidationContext()
            );
            if (target == null || target.idValue == null) continue;
            if (criterion.AudienceType__c == TYPE_PUBLIC_GROUP) publicRootIds.add(target.idValue);
            if (criterion.AudienceType__c == TYPE_ROLE_INTERNAL ||
                criterion.AudienceType__c == TYPE_ROLE_PORTAL ||
                criterion.AudienceType__c == TYPE_ROLE_INTERNAL_PORTAL) {
                hierarchyRootIds.add(target.idValue);
            }
            if (criterion.AudienceType__c == TYPE_JOB_TITLE_AND_SUBORDINATES) {
                hasJobTitleAndSubordinatesCriterion = true;
            }
            if (criterion.AudienceType__c == TYPE_JOB_TITLE) {
                hasJobTitleCriterion = true;
            }
        }

        PublicGroupGraph publicGraph = loadPublicGroupGraph(publicRootIds, false);
        for (AudienceGroupRecord groupRecord : publicGraph.groupsById.values()) {
            if (isRolePublicGroupMember(groupRecord) && groupRecord.relatedId != null) {
                hierarchyRootIds.add(groupRecord.relatedId);
            }
        }
        Map<Id, Set<Id>> hierarchyByRoot = dataProvider.getRoleAndDescendantIdsByRoot(hierarchyRootIds);
        Set<Id> publicGroupsForCurrentUser = getPublicGroupsForCurrentUser(
            publicRootIds,
            publicGraph,
            currentUser,
            hierarchyByRoot
        );
        Set<Id> currentUserContactIds = new Set<Id>();
        Set<Id> currentUserContactJobTitleIds = new Set<Id>();
        if (hasJobTitleCriterion || hasJobTitleAndSubordinatesCriterion) {
            Integer initialContactSafeCapacity = getAuthorizationJobTitleInitialContactMaxContacts();
            List<AudienceContactRecord> currentUserContacts = dataProvider.getContactsByUserId(
                UserInfo.getUserId(),
                initialContactSafeCapacity + 1
            );
            assertJobTitleContactResultWithinCapacity(
                currentUserContacts.size(),
                initialContactSafeCapacity,
                JOB_TITLE_AUTH_LIMIT_MESSAGE
            );
            for (AudienceContactRecord contactRecord : currentUserContacts) {
                if (contactRecord == null || contactRecord.contactId == null) continue;
                currentUserContactIds.add(contactRecord.contactId);
                if (contactRecord.cargoId != null) currentUserContactJobTitleIds.add(contactRecord.cargoId);
            }
        }
        Set<Id> currentUserContactChainJobTitleIds = hasJobTitleAndSubordinatesCriterion
            ? loadContactChainJobTitleIdsForAuthorization(currentUserContactIds)
            : new Set<Id>();

        for (CommunicatorBroadcastAudience__c criterion : criteria) {
            if (result.get(criterion.CommunicatorGroup__c) == true) continue;
            ValidatedAudienceTarget target = validateCriterionStructure(
                criterion,
                false,
                new AudienceValidationContext()
            );
            if (target == null) continue;

            Boolean hasAccess = false;
            if (criterion.AudienceType__c == TYPE_DIRECT_USER) {
                hasAccess = target.idValue == currentUser.userId;
            } else if (criterion.AudienceType__c == TYPE_ROLE) {
                hasAccess = target.idValue == currentUser.userRoleId;
            } else if (criterion.AudienceType__c == TYPE_ROLE_INTERNAL) {
                hasAccess = isCore(currentUser) &&
                    roleContainsCurrentUser(target.idValue, currentUser, hierarchyByRoot);
            } else if (criterion.AudienceType__c == TYPE_ROLE_PORTAL) {
                hasAccess = isCommunityPartner(currentUser) &&
                    roleContainsCurrentUser(target.idValue, currentUser, hierarchyByRoot);
            } else if (criterion.AudienceType__c == TYPE_ROLE_INTERNAL_PORTAL) {
                hasAccess = roleContainsCurrentUser(target.idValue, currentUser, hierarchyByRoot);
            } else if (criterion.AudienceType__c == TYPE_PUBLIC_GROUP) {
                hasAccess = publicGroupsForCurrentUser.contains(target.idValue);
            } else if (criterion.AudienceType__c == TYPE_SALES_COMPANY) {
                hasAccess = String.isNotBlank(currentUser.salesCompany) &&
                    currentUser.salesCompany == target.textValue;
            } else if (criterion.AudienceType__c == TYPE_JOB_TITLE) {
                hasAccess = currentUserContactJobTitleIds.contains(target.idValue);
            } else if (criterion.AudienceType__c == TYPE_JOB_TITLE_AND_SUBORDINATES) {
                hasAccess = currentUserContactChainJobTitleIds.contains(target.idValue);
            } else if (criterion.AudienceType__c == TYPE_ALL_SUPPORTED_USERS) {
                hasAccess = true;
            }
            if (hasAccess) result.put(criterion.CommunicatorGroup__c, true);
        }
        return result;
    }

    public static Boolean canCurrentUserPublishToBroadcast(Id broadcastGroupId) {
        if (broadcastGroupId == null || !hasCreatorPermission()) return false;
        for (CommunicatorGroup__c groupRecord : dataProvider.getCommunicatorGroups(
            new Set<Id>{ broadcastGroupId }
        )) {
            return groupRecord.Type__c == GROUP_TYPE_BROADCAST &&
                groupRecord.IsActive__c == true &&
                groupRecord.CreatedByUser__c == UserInfo.getUserId();
        }
        return false;
    }

    public static Boolean currentUserHasCreatorPermission() {
        return hasCreatorPermission();
    }

    public static Boolean canCurrentUserCreateBroadcast() {
        return hasCreatorPermission();
    }

    public static Boolean hasActiveAudienceType(Id broadcastGroupId, String audienceType) {
        if (broadcastGroupId == null || String.isBlank(audienceType)) return false;
        String normalizedAudienceType = audienceType.trim();
        for (CommunicatorBroadcastAudience__c criterion : dataProvider.getActiveCriteria(
            new Set<Id>{ broadcastGroupId }
        )) {
            if (criterion.IsActive__c == true &&
                criterion.AudienceType__c == normalizedAudienceType) {
                return true;
            }
        }
        return false;
    }

    @TestVisible
    private static Integer getBroadcastNameMaxLength() {
        return CommunicatorGroup__c.Name.getDescribe().getLength();
    }

    @TestVisible
    private static Integer getBroadcastDescriptionMaxLength() {
        return CommunicatorGroup__c.Description__c.getDescribe().getLength();
    }

    private static String normalizeBroadcastName(String name) {
        return name == null ? null : name.trim();
    }

    private static String normalizeBroadcastDescription(String description) {
        String normalizedDescription = description == null ? null : description.trim();
        return String.isBlank(normalizedDescription) ? null : normalizedDescription;
    }

    private static String validateAndNormalizeBroadcastName(String name) {
        String normalizedName = normalizeBroadcastName(name);
        if (String.isBlank(normalizedName)) {
            throw new CommunicatorException(BROADCAST_NAME_REQUIRED_MESSAGE);
        }

        Integer maxLength = getBroadcastNameMaxLength();
        if (normalizedName.length() > maxLength) {
            throw new CommunicatorException(
                'O nome do comunicado deve ter no maximo ' + maxLength + ' caracteres.'
            );
        }
        return normalizedName;
    }

    private static String validateAndNormalizeBroadcastDescription(String description) {
        String normalizedDescription = normalizeBroadcastDescription(description);
        Integer maxLength = getBroadcastDescriptionMaxLength();
        if (normalizedDescription != null && normalizedDescription.length() > maxLength) {
            throw new CommunicatorException(
                'A descricao do comunicado deve ter no maximo ' + maxLength + ' caracteres.'
            );
        }
        return normalizedDescription;
    }

    public static CommunicatorGroup__c createBroadcastGroup(
        String name,
        String description,
        List<CommunicatorBroadcastAudience__c> criteria
    ) {
        return createBroadcastGroup(name, description, criteria, System.now());
    }

    public static CommunicatorGroup__c createBroadcastGroupForLwc(
        String name,
        String description,
        List<CommunicatorBroadcastAudience__c> criteria
    ) {
        return createBroadcastGroupForLwc(name, description, criteria, System.now());
    }

    public static CommunicatorGroup__c createBroadcastGroup(
        String name,
        String description,
        List<CommunicatorBroadcastAudience__c> criteria,
        Datetime broadcastLastActivityAt
    ) {
        return createBroadcastGroupInternal(
            name,
            description,
            criteria,
            broadcastLastActivityAt,
            false
        );
    }

    public static CommunicatorGroup__c createBroadcastGroupForLwc(
        String name,
        String description,
        List<CommunicatorBroadcastAudience__c> criteria,
        Datetime broadcastLastActivityAt
    ) {
        return createBroadcastGroupInternal(
            name,
            description,
            criteria,
            broadcastLastActivityAt,
            true
        );
    }

    private static CommunicatorGroup__c createBroadcastGroupInternal(
        String name,
        String description,
        List<CommunicatorBroadcastAudience__c> criteria,
        Datetime broadcastLastActivityAt,
        Boolean useLwcStructuralValidation
    ) {
        assertCreatorPermission();
        String normalizedName = validateAndNormalizeBroadcastName(name);
        String normalizedDescription = validateAndNormalizeBroadcastDescription(description);
        AudienceValidationContext validationContext = new AudienceValidationContext();
        validateCriteriaForPersistence(
            criteria,
            validationContext,
            useLwcStructuralValidation
        );
        Datetime activityAt = broadcastLastActivityAt == null ? System.now() : broadcastLastActivityAt;

        CommunicatorGroup__c groupRecord = new CommunicatorGroup__c(
            Name = normalizedName,
            Description__c = normalizedDescription,
            IsActive__c = true,
            MemberCount__c = 0,
            CreatedByUser__c = UserInfo.getUserId(),
            Type__c = GROUP_TYPE_BROADCAST,
            BroadcastLastActivityAt__c = activityAt
        );
        Savepoint savepoint = Database.setSavepoint();
        try {
            registerGroupDmlAuthorization(DML_INSERT, new List<CommunicatorGroup__c>{ groupRecord });
            try {
                insert groupRecord;
            } finally {
                clearDmlAuthorization();
            }
            List<CommunicatorBroadcastAudience__c> toInsert = buildPersistedCriteria(
                groupRecord.Id,
                criteria,
                validationContext
            );
            registerAudienceDmlAuthorization(DML_INSERT, toInsert);
            try {
                insert toInsert;
            } finally {
                clearDmlAuthorization();
            }
            return groupRecord;
        } catch (Exception ex) {
            Database.rollback(savepoint);
            throw ex;
        }
    }

    public static CommunicatorGroup__c saveBroadcastDetails(
        Id broadcastGroupId,
        String name,
        String description,
        List<CommunicatorBroadcastAudience__c> criteria
    ) {
        return saveBroadcastDetailsInternal(
            broadcastGroupId,
            name,
            description,
            criteria,
            false
        );
    }

    public static CommunicatorGroup__c saveBroadcastDetailsForLwc(
        Id broadcastGroupId,
        String name,
        String description,
        List<CommunicatorBroadcastAudience__c> criteria
    ) {
        return saveBroadcastDetailsInternal(
            broadcastGroupId,
            name,
            description,
            criteria,
            true
        );
    }

    private static CommunicatorGroup__c saveBroadcastDetailsInternal(
        Id broadcastGroupId,
        String name,
        String description,
        List<CommunicatorBroadcastAudience__c> criteria,
        Boolean useLwcStructuralValidation
    ) {
        assertCanCurrentUserManageBroadcast(broadcastGroupId);
        String normalizedName = validateAndNormalizeBroadcastName(name);
        String normalizedDescription = validateAndNormalizeBroadcastDescription(description);

        CommunicatorGroup__c groupRecord = lockBroadcastGroup(broadcastGroupId);
        groupRecord.Name = normalizedName;
        groupRecord.Description__c = normalizedDescription;

        Savepoint savepoint = Database.setSavepoint();
        try {
            registerGroupDmlAuthorization(DML_UPDATE, new List<CommunicatorGroup__c>{ groupRecord });
            try {
                update groupRecord;
            } finally {
                clearDmlAuthorization();
            }

            replaceAudienceCriteriaInternal(
                broadcastGroupId,
                criteria,
                useLwcStructuralValidation
            );
            return groupRecord;
        } catch (Exception ex) {
            Database.rollback(savepoint);
            throw ex;
        }
    }

    public static CommunicatorGroup__c archiveBroadcastGroup(Id broadcastGroupId) {
        assertCanCurrentUserManageBroadcast(broadcastGroupId);
        CommunicatorGroup__c groupRecord = lockBroadcastGroup(broadcastGroupId);
        groupRecord.IsActive__c = false;

        Savepoint savepoint = Database.setSavepoint();
        try {
            registerGroupDmlAuthorization(DML_UPDATE, new List<CommunicatorGroup__c>{ groupRecord });
            try {
                update groupRecord;
            } finally {
                clearDmlAuthorization();
            }
            return groupRecord;
        } catch (Exception ex) {
            Database.rollback(savepoint);
            throw ex;
        }
    }

    public static void updateBroadcastActivity(Id broadcastGroupId, Datetime activityAt) {
        assertCanCurrentUserManageBroadcast(broadcastGroupId);
        persistBroadcastActivity(lockBroadcastGroup(broadcastGroupId), activityAt);
    }

    public static void updateBroadcastActivityFromDistribution(Id broadcastMessageId, Datetime activityAt) {
        if (activityAt == null) throw new CommunicatorException('Informe a data de atividade do comunicado.');

        CommunicatorGroup__c groupRecord = resolveAndLockBroadcastGroupFromMessage(broadcastMessageId);
        if (groupRecord.BroadcastLastActivityAt__c != null &&
            groupRecord.BroadcastLastActivityAt__c >= activityAt) {
            return;
        }
        persistBroadcastActivity(groupRecord, activityAt);
    }

    private static void persistBroadcastActivity(
        CommunicatorGroup__c groupRecord,
        Datetime activityAt
    ) {
        if (activityAt == null) throw new CommunicatorException('Informe a data de atividade do comunicado.');
        if (groupRecord == null) throw new CommunicatorException('Comunicado nao encontrado ou inativo.');
        groupRecord.BroadcastLastActivityAt__c = activityAt;
        Savepoint savepoint = Database.setSavepoint();
        try {
            registerGroupDmlAuthorization(DML_UPDATE, new List<CommunicatorGroup__c>{ groupRecord });
            try {
                update groupRecord;
            } finally {
                clearDmlAuthorization();
            }
        } catch (Exception ex) {
            Database.rollback(savepoint);
            throw ex;
        }
    }

    private static CommunicatorGroup__c resolveAndLockBroadcastGroupFromMessage(Id broadcastMessageId) {
        if (broadcastMessageId == null) {
            throw new CommunicatorException('Informe a mensagem do comunicado.');
        }

        List<CommunicatorMessage__c> messages = [
            SELECT Thread__r.RecordId__c, Thread__r.RecordType__c
            FROM CommunicatorMessage__c
            WHERE Id = :broadcastMessageId
            LIMIT 1
        ];
        if (messages.isEmpty() ||
            messages[0].Thread__r == null ||
            messages[0].Thread__r.RecordType__c != 'CommunicatorGroup__c' ||
            String.isBlank(messages[0].Thread__r.RecordId__c)) {
            throw new CommunicatorException('Nao foi possivel identificar o comunicado da distribuicao.');
        }

        try {
            Id groupId = (Id) messages[0].Thread__r.RecordId__c;
            if (groupId.getSObjectType() != CommunicatorGroup__c.SObjectType) {
                throw new CommunicatorException('Nao foi possivel identificar o comunicado da distribuicao.');
            }
            return lockBroadcastGroup(groupId);
        } catch (CommunicatorException ex) {
            throw ex;
        } catch (Exception ex) {
            throw new CommunicatorException('Nao foi possivel identificar o comunicado da distribuicao.');
        }
    }

    private static CommunicatorGroup__c lockBroadcastGroup(Id broadcastGroupId) {
        if (broadcastGroupId == null) throw new CommunicatorException('Informe o comunicado.');
        List<CommunicatorGroup__c> groups = [
            SELECT Id, Name, Description__c, CreatedByUser__c, CreatedByUser__r.Name,
                   IsActive__c, MemberCount__c, Type__c, BroadcastLastActivityAt__c
            FROM CommunicatorGroup__c
            WHERE Id = :broadcastGroupId
            AND Type__c = :GROUP_TYPE_BROADCAST
            AND IsActive__c = true
            LIMIT 1
            FOR UPDATE
        ];
        if (groups.isEmpty()) throw new CommunicatorException('Comunicado não encontrado ou inativo.');
        return groups[0];
    }

    public static List<CommunicatorDTOs.UserResultDTO> searchBroadcastAudienceTargets(
        String audienceType,
        String keyword,
        Integer limitSize
    ) {
        String normalizedAudienceType = String.isBlank(audienceType) ? null : audienceType.trim();
        Integer safeLimit = limitSize != null && limitSize > 0 ? Math.min(limitSize, 50) : 10;
        if (normalizedAudienceType == TYPE_DIRECT_USER) {
            return searchDirectUsers(keyword, safeLimit);
        }
        if (normalizedAudienceType == TYPE_ROLE ||
            normalizedAudienceType == TYPE_ROLE_INTERNAL ||
            normalizedAudienceType == TYPE_ROLE_PORTAL ||
            normalizedAudienceType == TYPE_ROLE_INTERNAL_PORTAL) {
            return searchRoles(keyword, safeLimit);
        }
        if (normalizedAudienceType == TYPE_PUBLIC_GROUP) {
            return searchPublicGroups(keyword, safeLimit);
        }
        if (normalizedAudienceType == TYPE_SALES_COMPANY) {
            return searchSalesCompanies(keyword, safeLimit);
        }
        if (normalizedAudienceType == TYPE_JOB_TITLE ||
            normalizedAudienceType == TYPE_JOB_TITLE_AND_SUBORDINATES) {
            return searchJobTitles(keyword, safeLimit);
        }
        if (normalizedAudienceType == TYPE_ALL_SUPPORTED_USERS) {
            return new List<CommunicatorDTOs.UserResultDTO>();
        }
        throw new CommunicatorException('Tipo de público não suportado.');
    }

    public static void replaceAudienceCriteria(
        Id broadcastGroupId,
        List<CommunicatorBroadcastAudience__c> criteria
    ) {
        replaceAudienceCriteriaInternal(broadcastGroupId, criteria, false);
    }

    public static void replaceAudienceCriteriaForLwc(
        Id broadcastGroupId,
        List<CommunicatorBroadcastAudience__c> criteria
    ) {
        replaceAudienceCriteriaInternal(broadcastGroupId, criteria, true);
    }

    private static void replaceAudienceCriteriaInternal(
        Id broadcastGroupId,
        List<CommunicatorBroadcastAudience__c> criteria,
        Boolean useLwcStructuralValidation
    ) {
        assertCanCurrentUserManageBroadcast(broadcastGroupId);
        List<CommunicatorBroadcastAudience__c> existing = [
            SELECT Id, AudienceKey__c, AudienceType__c, TargetId__c, TargetName__c,
                   SortOrder__c, IsActive__c, CommunicatorGroup__c
            FROM CommunicatorBroadcastAudience__c
            WHERE CommunicatorGroup__c = :broadcastGroupId
        ];
        AudienceValidationContext validationContext = buildValidationContext(existing);
        validateCriteriaForPersistence(
            criteria,
            validationContext,
            useLwcStructuralValidation
        );

        Map<String, CommunicatorBroadcastAudience__c> desiredByKey = new Map<String, CommunicatorBroadcastAudience__c>();
        for (CommunicatorBroadcastAudience__c criterion : criteria) {
            canonicalizeCriterion(criterion, true, validationContext);
            String key = buildAudienceKey(broadcastGroupId, criterion.AudienceType__c, criterion.TargetId__c);
            desiredByKey.put(key, criterion);
        }
        List<CommunicatorBroadcastAudience__c> toUpdate = new List<CommunicatorBroadcastAudience__c>();
        for (CommunicatorBroadcastAudience__c current : existing) {
            CommunicatorBroadcastAudience__c desired = desiredByKey.remove(current.AudienceKey__c);
            if (desired == null) {
                if (current.IsActive__c == true) {
                    current.IsActive__c = false;
                    toUpdate.add(current);
                }
                continue;
            }
            current.TargetName__c = desired.TargetName__c;
            current.TargetId__c = desired.TargetId__c;
            current.SortOrder__c = desired.SortOrder__c;
            current.IsActive__c = true;
            current.AudienceKey__c = buildAudienceKey(
                broadcastGroupId,
                desired.AudienceType__c,
                desired.TargetId__c
            );
            toUpdate.add(current);
        }

        List<CommunicatorBroadcastAudience__c> toInsert = new List<CommunicatorBroadcastAudience__c>();
        for (String key : desiredByKey.keySet()) {
            CommunicatorBroadcastAudience__c desired = desiredByKey.get(key);
            toInsert.add(buildPersistedCriterion(broadcastGroupId, desired, validationContext));
        }
        Savepoint savepoint = Database.setSavepoint();
        try {
            if (!toUpdate.isEmpty()) {
                registerAudienceDmlAuthorization(DML_UPDATE, toUpdate);
                try {
                    update toUpdate;
                } finally {
                    clearDmlAuthorization();
                }
            }
            if (!toInsert.isEmpty()) {
                registerAudienceDmlAuthorization(DML_INSERT, toInsert);
                try {
                    insert toInsert;
                } finally {
                    clearDmlAuthorization();
                }
            }
        } catch (Exception ex) {
            Database.rollback(savepoint);
            throw ex;
        }
    }

    public static Boolean consumeGroupDmlAuthorization(
        String operation,
        List<CommunicatorGroup__c> records
    ) {
        return consumeDmlAuthorization(
            GROUP_OBJECT,
            operation,
            buildGroupSignatures(records, operation != DML_INSERT)
        );
    }

    public static Boolean consumeAudienceDmlAuthorization(
        String operation,
        List<CommunicatorBroadcastAudience__c> records
    ) {
        return consumeDmlAuthorization(
            AUDIENCE_OBJECT,
            operation,
            buildAudienceSignatures(records, operation != DML_INSERT)
        );
    }

    public static Set<Id> validateCurrentAudienceForPublish(Id broadcastGroupId) {
        assertCanCurrentUserManageBroadcast(broadcastGroupId);
        Set<Id> recipients = resolveRecipientUserIds(new Set<Id>{ broadcastGroupId });
        if (recipients.isEmpty()) throw new CommunicatorException(EMPTY_AUDIENCE_MESSAGE);
        return recipients;
    }

    private static void validateCriteriaForPersistence(
        List<CommunicatorBroadcastAudience__c> criteria,
        AudienceValidationContext validationContext,
        Boolean useLwcStructuralValidation
    ) {
        if (useLwcStructuralValidation == true) {
            validateCriteriaStructureOnly(criteria, validationContext);
            return;
        }
        validateCriteriaResolveRecipients(criteria, validationContext);
    }

    private static void validateCriteriaResolveRecipients(
        List<CommunicatorBroadcastAudience__c> criteria,
        AudienceValidationContext validationContext
    ) {
        if (criteria == null || criteria.isEmpty()) return;
        Map<String, Set<Id>> resolved = resolveCriteria(criteria, true, validationContext);
        if (containsActiveAllSupportedUsersCriterion(criteria)) return;
        if (!hasResolvedRecipients(resolved)) throw new CommunicatorException(EMPTY_AUDIENCE_MESSAGE);
    }

    private static void validateCriteriaResolveRecipients(List<CommunicatorBroadcastAudience__c> criteria) {
        validateCriteriaResolveRecipients(criteria, new AudienceValidationContext());
    }

    private static void validateCriteriaStructureOnly(
        List<CommunicatorBroadcastAudience__c> criteria,
        AudienceValidationContext validationContext
    ) {
        if (criteria == null || criteria.isEmpty()) return;
        preloadStructuralTargets(criteria, validationContext);
        Set<String> uniqueCriteria = new Set<String>();
        if (criteria == null) return;
        for (CommunicatorBroadcastAudience__c criterion : criteria) {
            ValidatedAudienceTarget target = canonicalizeCriterion(
                criterion,
                true,
                validationContext
            );
            String audienceKey = criterion != null && criterion.CommunicatorGroup__c != null
                ? String.valueOf(criterion.CommunicatorGroup__c)
                : 'UNSAVED';
            if (criterion == null || criterion.IsActive__c == false || target == null) continue;

            assertStructuralTargetExists(criterion.AudienceType__c, target, validationContext);
            String duplicateKey =
                audienceKey + '|' + criterion.AudienceType__c + '|' + target.getCanonicalTargetId();
            if (!uniqueCriteria.add(duplicateKey)) {
                throw new CommunicatorException('Existem critérios de público duplicados.');
            }
        }
    }

    private static void preloadStructuralTargets(
        List<CommunicatorBroadcastAudience__c> criteria,
        AudienceValidationContext validationContext
    ) {
        if (criteria == null || criteria.isEmpty() || validationContext == null) return;

        Set<Id> directUserIds = new Set<Id>();
        Set<Id> roleIds = new Set<Id>();
        Set<Id> publicGroupIds = new Set<Id>();
        Set<Id> jobTitleIds = new Set<Id>();

        for (CommunicatorBroadcastAudience__c criterion : criteria) {
            if (criterion == null || criterion.IsActive__c == false || String.isBlank(criterion.AudienceType__c)) {
                continue;
            }

            String audienceType = criterion.AudienceType__c.trim();
            if (audienceType == TYPE_ALL_SUPPORTED_USERS || audienceType == TYPE_SALES_COMPANY) continue;

            Id targetId = parseTargetId(criterion.TargetId__c);
            if (targetId == null) continue;

            if (audienceType == TYPE_DIRECT_USER && targetId.getSObjectType() == User.SObjectType) {
                directUserIds.add(targetId);
                continue;
            }
            if ((audienceType == TYPE_ROLE ||
                 audienceType == TYPE_ROLE_INTERNAL ||
                 audienceType == TYPE_ROLE_PORTAL ||
                 audienceType == TYPE_ROLE_INTERNAL_PORTAL) &&
                targetId.getSObjectType() == UserRole.SObjectType) {
                roleIds.add(targetId);
                continue;
            }
            if (audienceType == TYPE_PUBLIC_GROUP && targetId.getSObjectType() == Group.SObjectType) {
                publicGroupIds.add(targetId);
                continue;
            }
            if ((audienceType == TYPE_JOB_TITLE ||
                 audienceType == TYPE_JOB_TITLE_AND_SUBORDINATES) &&
                targetId.getSObjectType() == CargosDepartamentos__c.SObjectType) {
                jobTitleIds.add(targetId);
            }
        }

        for (AudienceUserRecord userRecord : dataProvider.getUsersByIds(directUserIds)) {
            if (userRecord != null && userRecord.userId != null) {
                validationContext.existingDirectUserIds.add(userRecord.userId);
            }
        }
        validationContext.existingRoleIds.addAll(dataProvider.getExistingRoleIds(roleIds));
        for (AudienceGroupRecord groupRecord : dataProvider.getGroupsByIds(publicGroupIds)) {
            if (groupRecord != null && groupRecord.groupId != null) {
                validationContext.groupsById.put(groupRecord.groupId, groupRecord);
            }
        }
        for (JobTitleRecord jobTitleRecord : dataProvider.getJobTitlesByIds(jobTitleIds)) {
            if (jobTitleRecord != null && jobTitleRecord.jobTitleId != null) {
                validationContext.jobTitlesById.put(jobTitleRecord.jobTitleId, jobTitleRecord);
            }
        }
    }

    private static Boolean hasResolvedRecipients(Map<String, Set<Id>> recipientsByAudience) {
        if (recipientsByAudience == null || recipientsByAudience.isEmpty()) return false;
        for (Set<Id> recipients : recipientsByAudience.values()) {
            if (recipients != null && !recipients.isEmpty()) return true;
        }
        return false;
    }

    @TestVisible
    private static Map<String, Set<Id>> resolveCriteria(
        List<CommunicatorBroadcastAudience__c> criteria,
        Boolean strictValidation
    ) {
        return resolveCriteria(criteria, strictValidation, new AudienceValidationContext());
    }

    @TestVisible
    private static Map<String, Set<Id>> resolveCriteria(
        List<CommunicatorBroadcastAudience__c> criteria,
        Boolean strictValidation,
        AudienceValidationContext validationContext
    ) {
        Map<String, Set<Id>> recipientsByAudience = new Map<String, Set<Id>>();
        Map<Id, Set<String>> audienceKeysByDirectUser = new Map<Id, Set<String>>();
        Map<String, Set<String>> audienceKeysBySalesCompany = new Map<String, Set<String>>();
        Map<Id, Set<String>> audienceKeysByJobTitle = new Map<Id, Set<String>>();
        Map<Id, Set<String>> audienceKeysByJobTitleAndSubordinates = new Map<Id, Set<String>>();
        Map<Id, Set<String>> audienceKeysByPublicRoot = new Map<Id, Set<String>>();
        List<RoleRule> roleRules = new List<RoleRule>();
        Set<String> uniqueCriteria = new Set<String>();

        if (criteria == null) return recipientsByAudience;
        for (CommunicatorBroadcastAudience__c criterion : criteria) {
            ValidatedAudienceTarget target = canonicalizeCriterion(
                criterion,
                strictValidation,
                validationContext
            );
            String audienceKey = criterion.CommunicatorGroup__c == null
                ? 'UNSAVED'
                : String.valueOf(criterion.CommunicatorGroup__c);
            ensureRecipientBucket(recipientsByAudience, audienceKey);
            if (criterion.IsActive__c == false) continue;

            if (target == null) continue;
            String duplicateKey =
                audienceKey + '|' + criterion.AudienceType__c + '|' + target.getCanonicalTargetId();
            if (!uniqueCriteria.add(duplicateKey)) {
                if (strictValidation) throw new CommunicatorException('Existem critérios de público duplicados.');
                continue;
            }

            if (criterion.AudienceType__c == TYPE_ALL_SUPPORTED_USERS) {
                continue;
            }

            Set<String> targetAudienceKeys = new Set<String>{ audienceKey };
            if (criterion.AudienceType__c == TYPE_DIRECT_USER) {
                addAudienceKeys(audienceKeysByDirectUser, target.idValue, targetAudienceKeys);
            } else if (criterion.AudienceType__c == TYPE_SALES_COMPANY) {
                addAudienceKeys(audienceKeysBySalesCompany, target.textValue, targetAudienceKeys);
            } else if (criterion.AudienceType__c == TYPE_JOB_TITLE) {
                addAudienceKeys(audienceKeysByJobTitle, target.idValue, targetAudienceKeys);
            } else if (criterion.AudienceType__c == TYPE_JOB_TITLE_AND_SUBORDINATES) {
                addAudienceKeys(audienceKeysByJobTitleAndSubordinates, target.idValue, targetAudienceKeys);
            } else if (criterion.AudienceType__c == TYPE_ROLE) {
                roleRules.add(new RoleRule(target.idValue, MODE_EXACT, targetAudienceKeys));
            } else if (criterion.AudienceType__c == TYPE_ROLE_INTERNAL) {
                roleRules.add(new RoleRule(target.idValue, MODE_INTERNAL, targetAudienceKeys));
            } else if (criterion.AudienceType__c == TYPE_ROLE_PORTAL) {
                roleRules.add(new RoleRule(target.idValue, MODE_PORTAL, targetAudienceKeys));
            } else if (criterion.AudienceType__c == TYPE_ROLE_INTERNAL_PORTAL) {
                roleRules.add(new RoleRule(target.idValue, MODE_ALL, targetAudienceKeys));
            } else if (criterion.AudienceType__c == TYPE_PUBLIC_GROUP) {
                addAudienceKeys(audienceKeysByPublicRoot, target.idValue, targetAudienceKeys);
            }
        }

        PublicGroupGraph publicGraph = loadPublicGroupGraph(audienceKeysByPublicRoot.keySet(), strictValidation);
        addPublicGroupMembersToResolution(
            audienceKeysByPublicRoot,
            publicGraph,
            audienceKeysByDirectUser,
            roleRules
        );
        resolveDirectUsers(audienceKeysByDirectUser, recipientsByAudience);
        resolveSalesCompanies(audienceKeysBySalesCompany, recipientsByAudience);
        resolveJobTitles(audienceKeysByJobTitle, recipientsByAudience);
        resolveJobTitleAndSubordinates(audienceKeysByJobTitleAndSubordinates, recipientsByAudience);
        resolveRoleRules(roleRules, recipientsByAudience, strictValidation);
        return recipientsByAudience;
    }

    private static ValidatedAudienceTarget validateCriterionStructure(
        CommunicatorBroadcastAudience__c criterion,
        Boolean strictValidation,
        AudienceValidationContext validationContext
    ) {
        if (criterion == null || String.isBlank(criterion.AudienceType__c)) {
            if (strictValidation) throw new CommunicatorException('Informe o tipo e o alvo do público.');
            return null;
        }
        criterion.AudienceType__c = criterion.AudienceType__c.trim();
        if (criterion.AudienceType__c == TYPE_ALL_SUPPORTED_USERS) {
            return new ValidatedAudienceTarget(
                TYPE_ALL_SUPPORTED_USERS,
                UserInfo.getOrganizationId(),
                null,
                ALL_SUPPORTED_USERS_TARGET_NAME
            );
        }
        if (criterion.AudienceType__c == TYPE_SALES_COMPANY) {
            return validateSalesCompanyTarget(
                criterion.TargetId__c,
                criterion.TargetName__c,
                strictValidation,
                validationContext
            );
        }
        if (criterion.AudienceType__c == TYPE_JOB_TITLE ||
            criterion.AudienceType__c == TYPE_JOB_TITLE_AND_SUBORDINATES) {
            return validateJobTitleTarget(
                criterion.TargetId__c,
                criterion.TargetName__c,
                strictValidation,
                criterion.AudienceType__c,
                validationContext
            );
        }
        if (criterion == null || String.isBlank(criterion.AudienceType__c) ||
            String.isBlank(criterion.TargetId__c)) {
            if (strictValidation) throw new CommunicatorException('Informe o tipo e o alvo do público.');
            return null;
        }

        Set<String> supportedTypes = new Set<String>{
            TYPE_ROLE, TYPE_ROLE_INTERNAL, TYPE_ROLE_PORTAL, TYPE_ROLE_INTERNAL_PORTAL,
            TYPE_PUBLIC_GROUP, TYPE_DIRECT_USER, TYPE_SALES_COMPANY, TYPE_JOB_TITLE,
            TYPE_JOB_TITLE_AND_SUBORDINATES, TYPE_ALL_SUPPORTED_USERS
        };
        if (!supportedTypes.contains(criterion.AudienceType__c)) {
            if (strictValidation) throw new CommunicatorException('Tipo de público não suportado.');
            return null;
        }

        Id targetId = parseTargetId(criterion.TargetId__c);
        Boolean validType = targetId != null && (
            (criterion.AudienceType__c == TYPE_DIRECT_USER && targetId.getSObjectType() == User.SObjectType) ||
            (criterion.AudienceType__c == TYPE_PUBLIC_GROUP && targetId.getSObjectType() == Group.SObjectType) ||
            (criterion.AudienceType__c == TYPE_ALL_SUPPORTED_USERS &&
             targetId.getSObjectType() == Organization.SObjectType &&
             targetId == UserInfo.getOrganizationId()) ||
            ((criterion.AudienceType__c == TYPE_ROLE ||
              criterion.AudienceType__c == TYPE_ROLE_INTERNAL ||
              criterion.AudienceType__c == TYPE_ROLE_PORTAL ||
              criterion.AudienceType__c == TYPE_ROLE_INTERNAL_PORTAL) &&
             targetId.getSObjectType() == UserRole.SObjectType)
        );
        if (!validType) {
            if (strictValidation) throw new CommunicatorException('O identificador não corresponde ao tipo de público.');
            return null;
        }
        return new ValidatedAudienceTarget(
            criterion.AudienceType__c,
            targetId,
            null,
            criterion.TargetName__c
        );
    }

    private static PublicGroupGraph loadPublicGroupGraph(Set<Id> rootGroupIds, Boolean strictValidation) {
        PublicGroupGraph graph = new PublicGroupGraph();
        if (rootGroupIds == null || rootGroupIds.isEmpty()) return graph;

        loadMissingPublicGroups(graph, rootGroupIds);
        for (Id rootGroupId : rootGroupIds) {
            AudienceGroupRecord root = graph.groupsById.get(rootGroupId);
            if (root == null || root.groupType != 'Regular') {
                throw new CommunicatorException(PUBLIC_GROUP_INVALID_MESSAGE);
            }
        }
        Set<Id> visitedGroupIds = new Set<Id>();
        Set<Id> frontier = new Set<Id>();
        frontier.addAll(rootGroupIds);
        Integer depth = 0;
        Integer totalMemberRows = 0;

        while (!frontier.isEmpty()) {
            if (depth >= MAX_PUBLIC_GROUP_DEPTH) {
                throw new CommunicatorException(PUBLIC_GROUP_LIMIT_MESSAGE);
            }
            depth++;

            Set<Id> currentFrontier = new Set<Id>();
            for (Id groupId : frontier) {
                if (groupId != null && visitedGroupIds.add(groupId)) currentFrontier.add(groupId);
            }
            if (currentFrontier.isEmpty()) break;

            assertPublicGroupTraversalCapacity();
            Integer remainingMemberCapacity = MAX_PUBLIC_GROUP_MEMBERS - totalMemberRows;
            if (remainingMemberCapacity <= 0) throw new CommunicatorException(PUBLIC_GROUP_LIMIT_MESSAGE);
            Integer safeQueryLimit = Math.min(
                remainingMemberCapacity + 1,
                calculatePublicGroupSafeQueryRowCapacity()
            );
            if (safeQueryLimit <= 1 && remainingMemberCapacity > 0) {
                throw new CommunicatorException(PUBLIC_GROUP_LIMIT_MESSAGE);
            }

            List<AudienceGroupMemberRecord> levelMembers =
                dataProvider.getGroupMembersByGroupIds(currentFrontier, safeQueryLimit);
            if (levelMembers.size() > remainingMemberCapacity) {
                throw new CommunicatorException(PUBLIC_GROUP_LIMIT_MESSAGE);
            }
            totalMemberRows += levelMembers.size();

            Set<Id> memberGroupIds = new Set<Id>();
            for (AudienceGroupMemberRecord memberRecord : levelMembers) {
                if (memberRecord == null || memberRecord.memberId == null) continue;
                if (memberRecord.memberId.getSObjectType() == Group.SObjectType) {
                    memberGroupIds.add(memberRecord.memberId);
                }
            }
            loadMissingPublicGroups(graph, memberGroupIds);

            Set<Id> nextFrontier = new Set<Id>();
            for (AudienceGroupMemberRecord memberRecord : levelMembers) {
                if (memberRecord == null || memberRecord.groupId == null) continue;
                if (!graph.memberIdsByGroup.containsKey(memberRecord.groupId)) {
                    graph.memberIdsByGroup.put(memberRecord.groupId, new List<Id>());
                }
                graph.memberIdsByGroup.get(memberRecord.groupId).add(memberRecord.memberId);

                Id memberId = memberRecord.memberId;
                if (memberId == null || memberId.getSObjectType() == User.SObjectType) continue;
                if (memberId.getSObjectType() != Group.SObjectType) {
                    throwUnsupportedPublicGroupMemberType('Id');
                }

                AudienceGroupRecord memberGroup = graph.groupsById.get(memberId);
                if (memberGroup == null) throwUnsupportedPublicGroupMemberType('desconhecido');
                if (isExpandablePublicGroupMember(memberGroup)) {
                    if (!visitedGroupIds.contains(memberGroup.groupId)) nextFrontier.add(memberGroup.groupId);
                } else if (isRolePublicGroupMember(memberGroup)) {
                    assertValidPublicGroupRoleMember(memberGroup);
                } else {
                    throwUnsupportedPublicGroupMemberType(memberGroup.groupType);
                }
            }
            frontier = nextFrontier;
        }
        return graph;
    }

    private static void loadMissingPublicGroups(PublicGroupGraph graph, Set<Id> groupIds) {
        if (graph == null || groupIds == null || groupIds.isEmpty()) return;
        Set<Id> missingGroupIds = new Set<Id>();
        for (Id groupId : groupIds) {
            if (groupId != null && !graph.groupsById.containsKey(groupId)) missingGroupIds.add(groupId);
        }
        if (missingGroupIds.isEmpty()) return;
        assertPublicGroupTraversalCapacity();
        for (AudienceGroupRecord groupRecord : dataProvider.getGroupsByIds(missingGroupIds)) {
            if (groupRecord == null || groupRecord.groupId == null) continue;
            graph.groupsById.put(groupRecord.groupId, groupRecord);
        }
    }

    private static Boolean isExpandablePublicGroupMember(AudienceGroupRecord groupRecord) {
        return groupRecord != null &&
            (groupRecord.groupType == 'Regular' || groupRecord.groupType == 'Queue');
    }

    private static Boolean isRolePublicGroupMember(AudienceGroupRecord groupRecord) {
        return groupRecord != null &&
            (groupRecord.groupType == 'Role' ||
             groupRecord.groupType == 'RoleAndSubordinates' ||
             groupRecord.groupType == 'RoleAndSubordinatesInternal' ||
             groupRecord.groupType == 'RoleAndSubordinatesPortal' ||
             groupRecord.groupType == 'RoleAndSubordinatesInternalAndPortal');
    }

    private static void assertValidPublicGroupRoleMember(AudienceGroupRecord groupRecord) {
        if (groupRecord == null ||
            groupRecord.relatedId == null ||
            groupRecord.relatedId.getSObjectType() != UserRole.SObjectType) {
            throw new CommunicatorException(PUBLIC_GROUP_INVALID_ROLE_MEMBER_MESSAGE);
        }
    }

    private static void throwUnsupportedPublicGroupMemberType(String groupType) {
        String safeType = String.isBlank(groupType) ? 'desconhecido' : groupType.trim();
        throw new CommunicatorException(
            PUBLIC_GROUP_UNSUPPORTED_MEMBER_MESSAGE_PREFIX +
            safeType +
            PUBLIC_GROUP_UNSUPPORTED_MEMBER_MESSAGE_SUFFIX
        );
    }

    private static void assertPublicGroupTraversalCapacity() {
        if ((Limits.getLimitQueries() - Limits.getQueries()) <= PUBLIC_GROUP_QUERY_RESERVE ||
            (Limits.getLimitQueryRows() - Limits.getQueryRows()) <= PUBLIC_GROUP_ROW_RESERVE ||
            (Limits.getLimitCpuTime() - Limits.getCpuTime()) <= PUBLIC_GROUP_CPU_RESERVE_MS ||
            (Limits.getLimitHeapSize() - Limits.getHeapSize()) <= PUBLIC_GROUP_HEAP_RESERVE_BYTES) {
            throw new CommunicatorException(PUBLIC_GROUP_LIMIT_MESSAGE);
        }
    }

    private static Integer calculatePublicGroupSafeQueryRowCapacity() {
        Integer remainingRows = getRemainingGovernorCapacity(
            Limits.getLimitQueryRows(),
            Limits.getQueryRows(),
            PUBLIC_GROUP_ROW_RESERVE
        );
        if (remainingRows <= 0) throw new CommunicatorException(PUBLIC_GROUP_LIMIT_MESSAGE);
        return remainingRows;
    }

    private static void assertStructuralTargetExists(
        String audienceType,
        ValidatedAudienceTarget target,
        AudienceValidationContext validationContext
    ) {
        if (target == null || String.isBlank(audienceType)) return;
        if (audienceType == TYPE_DIRECT_USER) {
            Boolean userExists =
                validationContext != null && validationContext.existingDirectUserIds.contains(target.idValue);
            if (!userExists && dataProvider.getUsersByIds(new Set<Id>{ target.idValue }).isEmpty()) {
                throw new CommunicatorException('O usuario informado nao existe.');
            }
            return;
        }
        if (audienceType == TYPE_ROLE ||
            audienceType == TYPE_ROLE_INTERNAL ||
            audienceType == TYPE_ROLE_PORTAL ||
            audienceType == TYPE_ROLE_INTERNAL_PORTAL) {
            Boolean roleExists =
                validationContext != null && validationContext.existingRoleIds.contains(target.idValue);
            if (!roleExists &&
                !dataProvider.getExistingRoleIds(new Set<Id>{ target.idValue }).contains(target.idValue)) {
                throw new CommunicatorException('O papel selecionado não é válido.');
            }
            return;
        }
        if (audienceType != TYPE_PUBLIC_GROUP) return;
        AudienceGroupRecord groupRecord =
            validationContext == null ? null : validationContext.groupsById.get(target.idValue);
        if (groupRecord == null) {
            List<AudienceGroupRecord> groups = dataProvider.getGroupsByIds(new Set<Id>{ target.idValue });
            groupRecord = groups.isEmpty() ? null : groups[0];
        }
        if (groupRecord == null || groupRecord.groupType != 'Regular') {
            throw new CommunicatorException(PUBLIC_GROUP_INVALID_MESSAGE);
        }
    }

    private static void addPublicGroupMembersToResolution(
        Map<Id, Set<String>> audienceKeysByPublicRoot,
        PublicGroupGraph graph,
        Map<Id, Set<String>> audienceKeysByDirectUser,
        List<RoleRule> roleRules
    ) {
        for (Id rootGroupId : audienceKeysByPublicRoot.keySet()) {
            if (!graph.groupsById.containsKey(rootGroupId) ||
                graph.groupsById.get(rootGroupId).groupType != 'Regular') continue;

            Set<Id> visitedGroups = new Set<Id>();
            Set<Id> frontier = new Set<Id>{ rootGroupId };
            Integer depth = 0;
            while (!frontier.isEmpty() && depth < MAX_PUBLIC_GROUP_DEPTH) {
                depth++;
                Set<Id> next = new Set<Id>();
                for (Id currentGroupId : frontier) {
                    if (!visitedGroups.add(currentGroupId)) continue;
                    List<Id> memberIds = graph.memberIdsByGroup.get(currentGroupId);
                    if (memberIds == null) continue;
                    for (Id memberId : memberIds) {
                        if (memberId == null) continue;
                        if (memberId.getSObjectType() == User.SObjectType) {
                            addAudienceKeys(
                                audienceKeysByDirectUser,
                                memberId,
                                audienceKeysByPublicRoot.get(rootGroupId)
                            );
                            continue;
                        }
                        if (memberId.getSObjectType() != Group.SObjectType) continue;
                        AudienceGroupRecord memberGroup = graph.groupsById.get(memberId);
                        if (memberGroup == null) continue;
                        if (isExpandablePublicGroupMember(memberGroup)) {
                            if (!visitedGroups.contains(memberGroup.groupId)) next.add(memberGroup.groupId);
                        } else if (memberGroup.groupType == 'Role' && memberGroup.relatedId != null) {
                            roleRules.add(new RoleRule(
                                memberGroup.relatedId,
                                MODE_EXACT,
                                audienceKeysByPublicRoot.get(rootGroupId),
                                true
                            ));
                        } else if (memberGroup.groupType == 'RoleAndSubordinates' && memberGroup.relatedId != null) {
                            roleRules.add(new RoleRule(
                                memberGroup.relatedId,
                                MODE_ALL,
                                audienceKeysByPublicRoot.get(rootGroupId),
                                true
                            ));
                        } else if (memberGroup.groupType == 'RoleAndSubordinatesInternal' && memberGroup.relatedId != null) {
                            roleRules.add(new RoleRule(
                                memberGroup.relatedId,
                                MODE_INTERNAL,
                                audienceKeysByPublicRoot.get(rootGroupId),
                                true
                            ));
                        } else if (memberGroup.groupType == 'RoleAndSubordinatesPortal' && memberGroup.relatedId != null) {
                            roleRules.add(new RoleRule(
                                memberGroup.relatedId,
                                MODE_PORTAL,
                                audienceKeysByPublicRoot.get(rootGroupId),
                                true
                            ));
                        } else if (memberGroup.groupType == 'RoleAndSubordinatesInternalAndPortal' &&
                            memberGroup.relatedId != null) {
                            roleRules.add(new RoleRule(
                                memberGroup.relatedId,
                                MODE_ALL,
                                audienceKeysByPublicRoot.get(rootGroupId),
                                true
                            ));
                        }
                    }
                }
                frontier = next;
            }
        }
    }

    private static void resolveDirectUsers(
        Map<Id, Set<String>> audienceKeysByUser,
        Map<String, Set<Id>> recipientsByAudience
    ) {
        if (audienceKeysByUser.isEmpty()) return;
        for (AudienceUserRecord userRecord : dataProvider.getUsersByIds(audienceKeysByUser.keySet())) {
            if (!isSupportedActiveUser(userRecord)) continue;
            for (String audienceKey : audienceKeysByUser.get(userRecord.userId)) {
                ensureRecipientBucket(recipientsByAudience, audienceKey).add(userRecord.userId);
            }
        }
    }

    private static void resolveSalesCompanies(
        Map<String, Set<String>> audienceKeysBySalesCompany,
        Map<String, Set<Id>> recipientsByAudience
    ) {
        if (audienceKeysBySalesCompany.isEmpty()) return;
        for (AudienceUserRecord userRecord : dataProvider.getActiveUsersBySalesCompanies(
            audienceKeysBySalesCompany.keySet()
        )) {
            if (!isSupportedActiveUser(userRecord) ||
                String.isBlank(userRecord.salesCompany) ||
                !audienceKeysBySalesCompany.containsKey(userRecord.salesCompany)) {
                continue;
            }
            for (String audienceKey : audienceKeysBySalesCompany.get(userRecord.salesCompany)) {
                ensureRecipientBucket(recipientsByAudience, audienceKey).add(userRecord.userId);
            }
        }
    }

    private static void resolveJobTitles(
        Map<Id, Set<String>> audienceKeysByJobTitle,
        Map<String, Set<Id>> recipientsByAudience
    ) {
        if (audienceKeysByJobTitle.isEmpty()) return;
        List<AudienceContactRecord> activeUserContacts = dataProvider.getActiveUserContactsByJobTitleIds(
            audienceKeysByJobTitle.keySet(),
            null
        );
        for (AudienceContactRecord contactRecord : activeUserContacts) {
            AudienceUserRecord userRecord = toAudienceUserFromContact(contactRecord);
            if (!isSupportedActiveUser(userRecord) ||
                contactRecord == null ||
                contactRecord.cargoId == null ||
                contactRecord.usuarioId == null ||
                !audienceKeysByJobTitle.containsKey(contactRecord.cargoId)) {
                continue;
            }
            for (String audienceKey : audienceKeysByJobTitle.get(contactRecord.cargoId)) {
                ensureRecipientBucket(recipientsByAudience, audienceKey).add(contactRecord.usuarioId);
            }
        }
    }

    private static void resolveJobTitleAndSubordinates(
        Map<Id, Set<String>> audienceKeysByJobTitleAndSubordinates,
        Map<String, Set<Id>> recipientsByAudience
    ) {
        if (audienceKeysByJobTitleAndSubordinates.isEmpty()) return;

        Map<Id, Set<String>> audienceKeysByContactId = new Map<Id, Set<String>>();
        Map<Id, Set<String>> frontierAudienceKeysByContactId = new Map<Id, Set<String>>();
        Set<Id> visitedContactIds = new Set<Id>();

        Integer rootQuerySafeCapacity = calculatePublishJobTitleSubtreeSafeQueryCapacity(
            visitedContactIds.size(),
            0,
            0
        );
        List<AudienceContactRecord> rootContacts = dataProvider.getContactsByJobTitleIds(
            audienceKeysByJobTitleAndSubordinates.keySet(),
            rootQuerySafeCapacity + 1
        );
        assertJobTitleContactResultWithinCapacity(
            rootContacts.size(),
            rootQuerySafeCapacity,
            JOB_TITLE_AND_SUBORDINATES_LIMIT_MESSAGE
        );
        assertPublishJobTitleHierarchyCapacity(visitedContactIds.size(), 0);

        for (AudienceContactRecord contactRecord : rootContacts) {
            if (contactRecord == null ||
                contactRecord.contactId == null ||
                contactRecord.cargoId == null ||
                !audienceKeysByJobTitleAndSubordinates.containsKey(contactRecord.cargoId)) {
                continue;
            }
            Set<String> addedAudienceKeys = mergeAudienceKeysByContact(
                audienceKeysByContactId,
                contactRecord.contactId,
                audienceKeysByJobTitleAndSubordinates.get(contactRecord.cargoId)
            );
            if (!addedAudienceKeys.isEmpty()) {
                visitedContactIds.add(contactRecord.contactId);
                mergeAudienceKeysByContact(
                    frontierAudienceKeysByContactId,
                    contactRecord.contactId,
                    addedAudienceKeys
                );
            }
        }
        assertPublishJobTitleHierarchyCapacity(
            visitedContactIds.size(),
            frontierAudienceKeysByContactId.size()
        );

        while (!frontierAudienceKeysByContactId.isEmpty()) {
            Integer childQuerySafeCapacity = calculatePublishJobTitleSubtreeSafeQueryCapacity(
                visitedContactIds.size(),
                frontierAudienceKeysByContactId.size(),
                0
            );
            List<AudienceContactRecord> childContacts = dataProvider.getChildContactsByManagerIds(
                frontierAudienceKeysByContactId.keySet(),
                childQuerySafeCapacity + 1
            );
            assertJobTitleContactResultWithinCapacity(
                childContacts.size(),
                childQuerySafeCapacity,
                JOB_TITLE_AND_SUBORDINATES_LIMIT_MESSAGE
            );
            assertPublishJobTitleHierarchyCapacity(
                visitedContactIds.size(),
                frontierAudienceKeysByContactId.size()
            );

            Map<Id, Set<String>> nextFrontierAudienceKeysByContactId = new Map<Id, Set<String>>();
            for (AudienceContactRecord childContact : childContacts) {
                if (childContact == null ||
                    childContact.contactId == null ||
                    childContact.reportsToId == null) {
                    continue;
                }
                Set<String> inheritedAudienceKeys = frontierAudienceKeysByContactId.get(childContact.reportsToId);
                if (inheritedAudienceKeys == null || inheritedAudienceKeys.isEmpty()) continue;

                Set<String> addedAudienceKeys = mergeAudienceKeysByContact(
                    audienceKeysByContactId,
                    childContact.contactId,
                    inheritedAudienceKeys
                );
                if (addedAudienceKeys.isEmpty()) continue;

                visitedContactIds.add(childContact.contactId);
                mergeAudienceKeysByContact(
                    nextFrontierAudienceKeysByContactId,
                    childContact.contactId,
                    addedAudienceKeys
                );
            }
            assertPublishJobTitleHierarchyCapacity(
                visitedContactIds.size(),
                nextFrontierAudienceKeysByContactId.size()
            );
            frontierAudienceKeysByContactId = nextFrontierAudienceKeysByContactId;
        }

        if (audienceKeysByContactId.isEmpty()) return;
        Integer userQuerySafeCapacity = calculatePublishJobTitleSubtreeSafeQueryCapacity(
            visitedContactIds.size(),
            0,
            null
        );
        List<AudienceContactRecord> activeUserContacts = dataProvider.getActiveUserContactsByIds(
            audienceKeysByContactId.keySet(),
            userQuerySafeCapacity + 1
        );
        assertJobTitleContactResultWithinCapacity(
            activeUserContacts.size(),
            userQuerySafeCapacity,
            JOB_TITLE_AND_SUBORDINATES_LIMIT_MESSAGE
        );
        assertPublishJobTitleHierarchyCapacity(visitedContactIds.size(), 0);
        for (AudienceContactRecord contactRecord : activeUserContacts) {
            AudienceUserRecord userRecord = toAudienceUserFromContact(contactRecord);
            if (!isSupportedActiveUser(userRecord) ||
                contactRecord == null ||
                contactRecord.contactId == null ||
                contactRecord.usuarioId == null ||
                !audienceKeysByContactId.containsKey(contactRecord.contactId)) {
                continue;
            }
            for (String audienceKey : audienceKeysByContactId.get(contactRecord.contactId)) {
                ensureRecipientBucket(recipientsByAudience, audienceKey).add(contactRecord.usuarioId);
            }
        }
        assertPublishJobTitleHierarchyCapacity(visitedContactIds.size(), 0);
    }

    private static void resolveRoleRules(
        List<RoleRule> roleRules,
        Map<String, Set<Id>> recipientsByAudience,
        Boolean strictValidation
    ) {
        if (roleRules.isEmpty()) return;
        Set<Id> rootRoleIds = new Set<Id>();
        for (RoleRule rule : roleRules) rootRoleIds.add(rule.rootRoleId);
        Map<Id, Set<Id>> hierarchyByRoot = dataProvider.getRoleAndDescendantIdsByRoot(rootRoleIds);

        Set<Id> allRoleIds = new Set<Id>();
        for (RoleRule rule : roleRules) {
            Set<Id> roleIds = hierarchyByRoot.get(rule.rootRoleId);
            if (roleIds == null || roleIds.isEmpty()) {
                if (rule.requireResolvedRoot == true) {
                    throw new CommunicatorException(PUBLIC_GROUP_INVALID_ROLE_MEMBER_MESSAGE);
                }
                if (strictValidation) throw new CommunicatorException('O papel selecionado não é válido.');
                continue;
            }
            if (rule.mode == MODE_EXACT) allRoleIds.add(rule.rootRoleId);
            else allRoleIds.addAll(roleIds);
        }

        Map<Id, List<AudienceUserRecord>> usersByRole = new Map<Id, List<AudienceUserRecord>>();
        for (AudienceUserRecord userRecord : dataProvider.getActiveUsersByRoleIds(allRoleIds)) {
            if (!usersByRole.containsKey(userRecord.userRoleId)) {
                usersByRole.put(userRecord.userRoleId, new List<AudienceUserRecord>());
            }
            usersByRole.get(userRecord.userRoleId).add(userRecord);
        }

        for (RoleRule rule : roleRules) {
            Set<Id> resolvedRoleIds = rule.mode == MODE_EXACT
                ? new Set<Id>{ rule.rootRoleId }
                : hierarchyByRoot.get(rule.rootRoleId);
            if (resolvedRoleIds == null) continue;
            for (Id roleId : resolvedRoleIds) {
                List<AudienceUserRecord> roleUsers = usersByRole.get(roleId);
                if (roleUsers == null) continue;
                for (AudienceUserRecord userRecord : roleUsers) {
                    if (!roleModeAcceptsUser(rule.mode, userRecord)) continue;
                    for (String audienceKey : rule.audienceKeys) {
                        ensureRecipientBucket(recipientsByAudience, audienceKey).add(userRecord.userId);
                    }
                }
            }
        }
    }

    private static Set<Id> loadContactChainJobTitleIdsForAuthorization(Set<Id> initialContactIds) {
        Set<Id> jobTitleIds = new Set<Id>();
        if (initialContactIds == null || initialContactIds.isEmpty()) return jobTitleIds;

        Set<Id> visitedContactIds = new Set<Id>();
        Set<Id> frontierContactIds = new Set<Id>();
        frontierContactIds.addAll(initialContactIds);
        while (!frontierContactIds.isEmpty()) {
            assertAuthorizationJobTitleHierarchyCapacity(
                visitedContactIds.size(),
                frontierContactIds.size()
            );
            List<AudienceContactRecord> contactChainLevel = dataProvider.getContactsByIds(frontierContactIds);
            assertAuthorizationJobTitleHierarchyCapacity(
                visitedContactIds.size(),
                frontierContactIds.size()
            );

            Set<Id> nextFrontierContactIds = new Set<Id>();
            for (AudienceContactRecord contactRecord : contactChainLevel) {
                if (contactRecord == null || contactRecord.contactId == null) continue;
                if (!visitedContactIds.add(contactRecord.contactId)) continue;
                if (contactRecord.cargoId != null) jobTitleIds.add(contactRecord.cargoId);
                if (contactRecord.reportsToId != null &&
                    !visitedContactIds.contains(contactRecord.reportsToId)) {
                    nextFrontierContactIds.add(contactRecord.reportsToId);
                }
            }
            assertAuthorizationJobTitleHierarchyCapacity(
                visitedContactIds.size(),
                nextFrontierContactIds.size()
            );
            frontierContactIds = nextFrontierContactIds;
        }
        return jobTitleIds;
    }

    private static Set<Id> getPublicGroupsForCurrentUser(
        Set<Id> rootGroupIds,
        PublicGroupGraph graph,
        AudienceUserRecord currentUser,
        Map<Id, Set<Id>> hierarchyByRoot
    ) {
        Set<Id> result = new Set<Id>();
        for (Id rootGroupId : rootGroupIds) {
            if (!graph.groupsById.containsKey(rootGroupId) ||
                graph.groupsById.get(rootGroupId).groupType != 'Regular') continue;
            Set<Id> visited = new Set<Id>();
            Set<Id> frontier = new Set<Id>{ rootGroupId };
            Integer depth = 0;
            Boolean found = false;
            while (!frontier.isEmpty() && depth < MAX_PUBLIC_GROUP_DEPTH && !found) {
                depth++;
                Set<Id> next = new Set<Id>();
                for (Id currentGroupId : frontier) {
                    if (!visited.add(currentGroupId)) continue;
                    List<Id> memberIds = graph.memberIdsByGroup.get(currentGroupId);
                    if (memberIds == null) continue;
                    for (Id memberId : memberIds) {
                        if (memberId == currentUser.userId) {
                            found = true;
                            break;
                        }
                        if (memberId == null || memberId.getSObjectType() != Group.SObjectType) continue;
                        AudienceGroupRecord memberGroup = graph.groupsById.get(memberId);
                        if (memberGroup == null) continue;
                        if (isExpandablePublicGroupMember(memberGroup)) {
                            if (!visited.contains(memberGroup.groupId)) next.add(memberGroup.groupId);
                        } else if (currentUserMatchesSystemGroup(currentUser, memberGroup, hierarchyByRoot)) {
                            found = true;
                            break;
                        }
                    }
                    if (found) break;
                }
                frontier = next;
            }
            if (found) result.add(rootGroupId);
        }
        return result;
    }

    private static Boolean currentUserMatchesSystemGroup(
        AudienceUserRecord currentUser,
        AudienceGroupRecord groupRecord,
        Map<Id, Set<Id>> hierarchyByRoot
    ) {
        if (currentUser.userRoleId == null || groupRecord.relatedId == null) return false;
        if (groupRecord.groupType == 'Role') return currentUser.userRoleId == groupRecord.relatedId;
        if (groupRecord.groupType == 'RoleAndSubordinates') {
            return roleContainsCurrentUser(groupRecord.relatedId, currentUser, hierarchyByRoot);
        }
        if (groupRecord.groupType == 'RoleAndSubordinatesInternal') {
            return isCore(currentUser) &&
                roleContainsCurrentUser(groupRecord.relatedId, currentUser, hierarchyByRoot);
        }
        if (groupRecord.groupType == 'RoleAndSubordinatesPortal') {
            return isCommunityPartner(currentUser) &&
                roleContainsCurrentUser(groupRecord.relatedId, currentUser, hierarchyByRoot);
        }
        if (groupRecord.groupType == 'RoleAndSubordinatesInternalAndPortal') {
            return roleContainsCurrentUser(groupRecord.relatedId, currentUser, hierarchyByRoot);
        }
        return false;
    }

    private static Boolean roleContainsCurrentUser(
        Id rootRoleId,
        AudienceUserRecord currentUser,
        Map<Id, Set<Id>> hierarchyByRoot
    ) {
        Set<Id> roleIds = hierarchyByRoot.get(rootRoleId);
        return currentUser.userRoleId != null && roleIds != null && roleIds.contains(currentUser.userRoleId);
    }

    private static UserAudienceCategory classifyUser(AudienceUserRecord userRecord) {
        if (userRecord == null || userRecord.isActive != true) return UserAudienceCategory.UNSUPPORTED;
        if (userRecord.userType == 'Standard' && userRecord.licenseName == 'Salesforce') {
            return UserAudienceCategory.CORE_SALESFORCE;
        }
        if (userRecord.userType == 'Standard' && userRecord.licenseName == 'Salesforce Platform') {
            return UserAudienceCategory.CORE_PLATFORM;
        }
        if (userRecord.userType == 'PowerPartner' &&
            (userRecord.licenseName == 'Partner Community' ||
             userRecord.licenseName == 'Partner Community Login')) {
            return UserAudienceCategory.COMMUNITY_PARTNER;
        }
        return UserAudienceCategory.UNSUPPORTED;
    }

    private static Boolean isSupportedActiveUser(AudienceUserRecord userRecord) {
        return classifyUser(userRecord) != UserAudienceCategory.UNSUPPORTED;
    }

    private static Boolean roleModeAcceptsUser(String mode, AudienceUserRecord userRecord) {
        UserAudienceCategory category = classifyUser(userRecord);
        if (category == UserAudienceCategory.UNSUPPORTED) return false;
        if (mode == MODE_INTERNAL) {
            return category == UserAudienceCategory.CORE_SALESFORCE ||
                category == UserAudienceCategory.CORE_PLATFORM;
        }
        if (mode == MODE_PORTAL) {
            return category == UserAudienceCategory.COMMUNITY_PARTNER;
        }
        return true;
    }

    private static Boolean isCore(AudienceUserRecord userRecord) {
        UserAudienceCategory category = classifyUser(userRecord);
        return category == UserAudienceCategory.CORE_SALESFORCE ||
            category == UserAudienceCategory.CORE_PLATFORM;
    }

    private static Boolean isCommunityPartner(AudienceUserRecord userRecord) {
        return classifyUser(userRecord) == UserAudienceCategory.COMMUNITY_PARTNER;
    }

    private static Set<Id> getValidBroadcastGroupIds(Set<Id> groupIds, Boolean requireActive) {
        Set<Id> result = new Set<Id>();
        if (groupIds == null || groupIds.isEmpty()) return result;
        for (CommunicatorGroup__c groupRecord : dataProvider.getCommunicatorGroups(groupIds)) {
            if (groupRecord.Type__c != GROUP_TYPE_BROADCAST) continue;
            if (requireActive && groupRecord.IsActive__c != true) continue;
            result.add(groupRecord.Id);
        }
        return result;
    }

    private static void assertCanCurrentUserManageBroadcast(Id broadcastGroupId) {
        if (!canCurrentUserPublishToBroadcast(broadcastGroupId)) {
            throw new CommunicatorException('Somente o criador autorizado pode alterar este comunicado.');
        }
    }

    private static void assertCreatorPermission() {
        if (!hasCreatorPermission()) {
            throw new CommunicatorException('Você não possui permissão para criar ou publicar comunicados.');
        }
    }

    private static Boolean hasCreatorPermission() {
        if (Test.isRunningTest() && forceCreatorPermissionForTest != null) {
            return forceCreatorPermissionForTest;
        }
        return FeatureManagement.checkPermission('CommunicatorBroadcastCreator');
    }

    @TestVisible
    private static void registerGroupDmlAuthorization(
        String operation,
        List<CommunicatorGroup__c> records
    ) {
        registerDmlAuthorization(
            GROUP_OBJECT,
            operation,
            buildGroupSignatures(records, operation != DML_INSERT)
        );
    }

    private static void registerAudienceDmlAuthorization(
        String operation,
        List<CommunicatorBroadcastAudience__c> records
    ) {
        registerDmlAuthorization(
            AUDIENCE_OBJECT,
            operation,
            buildAudienceSignatures(records, operation != DML_INSERT)
        );
    }

    private static void registerDmlAuthorization(
        String objectApiName,
        String operation,
        List<String> signatures
    ) {
        if (pendingDmlAuthorization != null) {
            throw new CommunicatorException('Existe uma operacao Broadcast controlada ainda nao consumida.');
        }
        pendingDmlAuthorization = new DmlAuthorization(
            objectApiName,
            operation,
            normalizeSignatures(signatures)
        );
    }

    private static Boolean consumeDmlAuthorization(
        String objectApiName,
        String operation,
        List<String> signatures
    ) {
        if (pendingDmlAuthorization == null ||
            pendingDmlAuthorization.objectApiName != objectApiName ||
            pendingDmlAuthorization.operation != operation ||
            pendingDmlAuthorization.expectedCount != signatures.size()) {
            return false;
        }

        List<String> actualSignatures = normalizeSignatures(signatures);
        for (Integer index = 0; index < actualSignatures.size(); index++) {
            if (actualSignatures[index] != pendingDmlAuthorization.expectedSignatures[index]) {
                return false;
            }
        }
        pendingDmlAuthorization = null;
        return true;
    }

    private static void clearDmlAuthorization() {
        pendingDmlAuthorization = null;
    }

    private static List<String> buildGroupSignatures(
        List<CommunicatorGroup__c> records,
        Boolean includeId
    ) {
        List<String> result = new List<String>();
        if (records == null) return result;
        for (CommunicatorGroup__c record : records) {
            result.add(String.join(new List<String>{
                signaturePart(includeId ? record.Id : null),
                signaturePart(record.Name),
                signaturePart(record.Description__c),
                signaturePart(record.IsActive__c),
                signaturePart(record.MemberCount__c),
                signaturePart(record.CreatedByUser__c),
                signaturePart(record.Type__c),
                signaturePart(record.BroadcastLastActivityAt__c)
            }, '|'));
        }
        return result;
    }

    private static List<String> buildAudienceSignatures(
        List<CommunicatorBroadcastAudience__c> records,
        Boolean includeId
    ) {
        List<String> result = new List<String>();
        if (records == null) return result;
        for (CommunicatorBroadcastAudience__c record : records) {
            result.add(String.join(new List<String>{
                signaturePart(includeId ? record.Id : null),
                signaturePart(record.CommunicatorGroup__c),
                signaturePart(record.AudienceKey__c),
                signaturePart(record.AudienceType__c),
                signaturePart(record.TargetId__c),
                signaturePart(record.TargetName__c),
                signaturePart(record.SortOrder__c),
                signaturePart(record.IsActive__c)
            }, '|'));
        }
        return result;
    }

    private static String signaturePart(Object value) {
        if (value == null) return '-1:';
        String serialized = String.valueOf(value);
        return String.valueOf(serialized.length()) + ':' + serialized;
    }

    private static List<CommunicatorDTOs.UserResultDTO> searchDirectUsers(String keyword, Integer limitSize) {
        List<CommunicatorDTOs.UserResultDTO> result = new List<CommunicatorDTOs.UserResultDTO>();
        String term = normalizeSearchTerm(keyword);
        if (term.length() < 2) return result;

        String likeTerm = '%' + term.replaceAll('\\s+', '%') + '%';
        Integer probeLimit = Math.min(Math.max(limitSize * 5, limitSize + 5), 100);
        for (User userRecord : [
            SELECT Id, Name, IsActive, UserType, UserRoleId, Profile.UserLicense.Name
            FROM User
            WHERE IsActive = true
            AND Name LIKE :likeTerm
            ORDER BY Name
            LIMIT :probeLimit
        ]) {
            AudienceUserRecord user = new AudienceUserRecord(
                userRecord.Id,
                userRecord.IsActive,
                userRecord.UserType,
                userRecord.Profile != null && userRecord.Profile.UserLicense != null
                    ? userRecord.Profile.UserLicense.Name
                    : null,
                userRecord.UserRoleId
            );
            if (!isSupportedActiveUser(user)) continue;
            CommunicatorDTOs.UserResultDTO dto = new CommunicatorDTOs.UserResultDTO();
            dto.id = String.valueOf(user.userId);
            dto.name = userRecord.Name;
            result.add(dto);
            if (result.size() >= limitSize) break;
        }
        return result;
    }

    private static List<CommunicatorDTOs.UserResultDTO> searchRoles(String keyword, Integer limitSize) {
        List<CommunicatorDTOs.UserResultDTO> result = new List<CommunicatorDTOs.UserResultDTO>();
        String term = normalizeSearchTerm(keyword);
        if (term.length() < 2) return result;

        String likeTerm = '%' + term.replaceAll('\\s+', '%') + '%';
        for (UserRole roleRecord : [
            SELECT Id, Name
            FROM UserRole
            WHERE Name LIKE :likeTerm
            ORDER BY Name
            LIMIT :limitSize
        ]) {
            CommunicatorDTOs.UserResultDTO dto = new CommunicatorDTOs.UserResultDTO();
            dto.id = String.valueOf(roleRecord.Id);
            dto.name = roleRecord.Name;
            result.add(dto);
        }
        return result;
    }

    private static List<CommunicatorDTOs.UserResultDTO> searchPublicGroups(String keyword, Integer limitSize) {
        List<CommunicatorDTOs.UserResultDTO> result = new List<CommunicatorDTOs.UserResultDTO>();
        String term = normalizeSearchTerm(keyword);
        if (term.length() < 2) return result;

        String likeTerm = '%' + term.replaceAll('\\s+', '%') + '%';
        for (Group groupRecord : [
            SELECT Id, Name
            FROM Group
            WHERE Type = 'Regular'
            AND Name LIKE :likeTerm
            ORDER BY Name
            LIMIT :limitSize
        ]) {
            CommunicatorDTOs.UserResultDTO dto = new CommunicatorDTOs.UserResultDTO();
            dto.id = String.valueOf(groupRecord.Id);
            dto.name = groupRecord.Name;
            result.add(dto);
        }
        return result;
    }

    private static List<CommunicatorDTOs.UserResultDTO> searchSalesCompanies(
        String keyword,
        Integer limitSize
    ) {
        List<CommunicatorDTOs.UserResultDTO> result = new List<CommunicatorDTOs.UserResultDTO>();
        String term = normalizeSearchTerm(keyword);
        if (term.length() < 2) return result;

        String loweredTerm = term.toLowerCase();
        for (AudiencePicklistOptionRecord option : dataProvider.getSalesCompanyPicklistOptions()) {
            if (option == null || option.isActive != true || String.isBlank(option.value)) continue;
            String searchable = (option.value + ' ' + option.label).toLowerCase();
            if (!searchable.contains(loweredTerm)) continue;

            CommunicatorDTOs.UserResultDTO dto = new CommunicatorDTOs.UserResultDTO();
            dto.id = option.value;
            dto.name = String.isNotBlank(option.label) ? option.label : option.value;
            result.add(dto);
            if (result.size() >= limitSize) break;
        }
        return result;
    }

    private static List<CommunicatorDTOs.UserResultDTO> searchJobTitles(
        String keyword,
        Integer limitSize
    ) {
        List<CommunicatorDTOs.UserResultDTO> result = new List<CommunicatorDTOs.UserResultDTO>();
        for (JobTitleRecord jobTitle : dataProvider.searchJobTitles(keyword, limitSize)) {
            CommunicatorDTOs.UserResultDTO dto = new CommunicatorDTOs.UserResultDTO();
            dto.id = String.valueOf(jobTitle.jobTitleId);
            dto.name = jobTitle.name;
            result.add(dto);
        }
        return result;
    }

    private static String normalizeSearchTerm(String keyword) {
        return String.isBlank(keyword) ? '' : keyword.trim();
    }

    private static List<String> normalizeSignatures(List<String> signatures) {
        List<String> result = new List<String>();
        if (signatures != null) result.addAll(signatures);
        result.sort();
        return result;
    }

    private static List<CommunicatorBroadcastAudience__c> buildPersistedCriteria(
        Id groupId,
        List<CommunicatorBroadcastAudience__c> criteria
    ) {
        return buildPersistedCriteria(groupId, criteria, new AudienceValidationContext());
    }

    private static List<CommunicatorBroadcastAudience__c> buildPersistedCriteria(
        Id groupId,
        List<CommunicatorBroadcastAudience__c> criteria,
        AudienceValidationContext validationContext
    ) {
        List<CommunicatorBroadcastAudience__c> result = new List<CommunicatorBroadcastAudience__c>();
        for (CommunicatorBroadcastAudience__c criterion : criteria) {
            result.add(buildPersistedCriterion(groupId, criterion, validationContext));
        }
        return result;
    }

    private static CommunicatorBroadcastAudience__c buildPersistedCriterion(
        Id groupId,
        CommunicatorBroadcastAudience__c source
    ) {
        return buildPersistedCriterion(groupId, source, new AudienceValidationContext());
    }

    private static CommunicatorBroadcastAudience__c buildPersistedCriterion(
        Id groupId,
        CommunicatorBroadcastAudience__c source,
        AudienceValidationContext validationContext
    ) {
        ValidatedAudienceTarget target = canonicalizeCriterion(source, true, validationContext);
        return new CommunicatorBroadcastAudience__c(
            CommunicatorGroup__c = groupId,
            AudienceType__c = source.AudienceType__c,
            TargetId__c = target.getCanonicalTargetId(),
            TargetName__c = source.TargetName__c,
            SortOrder__c = source.SortOrder__c,
            IsActive__c = true,
            AudienceKey__c = buildAudienceKey(
                groupId,
                source.AudienceType__c,
                target.getCanonicalTargetId()
            )
        );
    }

    private static String buildAudienceKey(Id groupId, String audienceType, String targetId) {
        if (audienceType == TYPE_ALL_SUPPORTED_USERS) {
            targetId = UserInfo.getOrganizationId();
        }
        if (audienceType == TYPE_SALES_COMPANY) {
            return String.valueOf(groupId) + '|' + audienceType + '|v1:' + buildSalesCompanyDigest(targetId);
        }
        Id parsedTargetId = parseTargetId(targetId);
        return String.valueOf(groupId) + '|' + audienceType + '|' + String.valueOf(parsedTargetId);
    }

    private static ValidatedAudienceTarget canonicalizeCriterion(
        CommunicatorBroadcastAudience__c criterion,
        Boolean strictValidation,
        AudienceValidationContext validationContext
    ) {
        ValidatedAudienceTarget target = validateCriterionStructure(
            criterion,
            strictValidation,
            validationContext
        );
        if (criterion == null || target == null) return target;
        criterion.TargetId__c = target.getCanonicalTargetId();
        criterion.TargetName__c = target.targetName;
        return target;
    }

    private static Boolean containsActiveAllSupportedUsersCriterion(
        List<CommunicatorBroadcastAudience__c> criteria
    ) {
        if (criteria == null || criteria.isEmpty()) return false;
        for (CommunicatorBroadcastAudience__c criterion : criteria) {
            canonicalizeCriterion(criterion, false, new AudienceValidationContext());
            if (criterion != null &&
                criterion.IsActive__c != false &&
                criterion.AudienceType__c == TYPE_ALL_SUPPORTED_USERS) {
                return true;
            }
        }
        return false;
    }

    private static AudienceValidationContext buildValidationContext(
        List<CommunicatorBroadcastAudience__c> existingCriteria
    ) {
        AudienceValidationContext context = new AudienceValidationContext();
        if (existingCriteria == null) return context;
        for (CommunicatorBroadcastAudience__c criterion : existingCriteria) {
            if (criterion != null &&
                criterion.IsActive__c == true &&
                criterion.AudienceType__c == TYPE_SALES_COMPANY &&
                String.isNotBlank(criterion.TargetId__c)) {
                context.allowedPersistedInactiveSalesCompanies.add(criterion.TargetId__c);
            }
        }
        return context;
    }

    private static ValidatedAudienceTarget validateSalesCompanyTarget(
        String rawTargetId,
        String currentTargetName,
        Boolean strictValidation,
        AudienceValidationContext validationContext
    ) {
        if (String.isBlank(rawTargetId)) {
            if (strictValidation) throw new CommunicatorException('Informe a empresa de vendas.');
            return null;
        }

        Map<String, AudiencePicklistOptionRecord> optionsByValue = getSalesCompanyOptionsByValue();
        AudiencePicklistOptionRecord option = optionsByValue.get(rawTargetId);
        if (option != null && option.isActive == true) {
            return new ValidatedAudienceTarget(
                TYPE_SALES_COMPANY,
                null,
                option.value,
                String.isNotBlank(option.label) ? option.label : option.value
            );
        }
        if (strictValidation &&
            (validationContext == null ||
             !validationContext.allowedPersistedInactiveSalesCompanies.contains(rawTargetId))) {
            throw new CommunicatorException('A empresa de vendas informada nao esta ativa ou nao existe.');
        }
        return new ValidatedAudienceTarget(
            TYPE_SALES_COMPANY,
            null,
            rawTargetId,
            String.isNotBlank(currentTargetName)
                ? currentTargetName
                : (option != null && String.isNotBlank(option.label) ? option.label : rawTargetId)
        );
    }

    private static ValidatedAudienceTarget validateJobTitleTarget(
        String rawTargetId,
        String currentTargetName,
        Boolean strictValidation,
        String audienceType,
        AudienceValidationContext validationContext
    ) {
        Id targetId = parseTargetId(rawTargetId);
        if (targetId == null || targetId.getSObjectType() != CargosDepartamentos__c.SObjectType) {
            if (strictValidation) {
                throw new CommunicatorException('O identificador nao corresponde ao tipo de publico.');
            }
            return null;
        }
        if (!strictValidation) {
            return new ValidatedAudienceTarget(audienceType, targetId, null, currentTargetName);
        }

        JobTitleRecord jobTitleRecord =
            validationContext == null ? null : validationContext.jobTitlesById.get(targetId);
        if (jobTitleRecord == null) {
            List<JobTitleRecord> jobTitles = dataProvider.getJobTitlesByIds(new Set<Id>{ targetId });
            jobTitleRecord = jobTitles.isEmpty() ? null : jobTitles[0];
        }
        if (jobTitleRecord == null) {
            throw new CommunicatorException('O cargo informado nao existe.');
        }
        return new ValidatedAudienceTarget(
            audienceType,
            jobTitleRecord.jobTitleId,
            null,
            jobTitleRecord.name
        );
    }

    private static Map<String, AudiencePicklistOptionRecord> getSalesCompanyOptionsByValue() {
        Map<String, AudiencePicklistOptionRecord> result = new Map<String, AudiencePicklistOptionRecord>();
        for (AudiencePicklistOptionRecord option : dataProvider.getSalesCompanyPicklistOptions()) {
            if (option == null || String.isBlank(option.value)) continue;
            result.put(option.value, option);
        }
        return result;
    }

    private static String buildSalesCompanyDigest(String value) {
        return EncodingUtil.convertToHex(
            Crypto.generateDigest('SHA-256', Blob.valueOf(value == null ? '' : value))
        ).toLowerCase();
    }

    private static void assertPublishJobTitleHierarchyCapacity(
        Integer visitedContactCount,
        Integer frontierContactCount
    ) {
        assertJobTitleHierarchyCapacity(
            visitedContactCount,
            frontierContactCount,
            getPublishJobTitleSubtreeQueryReserve(),
            getPublishJobTitleSubtreeRowReserve(),
            PUBLISH_JOB_TITLE_SUBTREE_CPU_RESERVE_MS,
            PUBLISH_JOB_TITLE_SUBTREE_HEAP_RESERVE_BYTES,
            getPublishJobTitleSubtreeMaxVisitedContacts(),
            getPublishJobTitleSubtreeMaxFrontierContacts(),
            JOB_TITLE_AND_SUBORDINATES_LIMIT_MESSAGE
        );
    }

    private static void assertAuthorizationJobTitleHierarchyCapacity(
        Integer visitedContactCount,
        Integer frontierContactCount
    ) {
        assertJobTitleHierarchyCapacity(
            visitedContactCount,
            frontierContactCount,
            getAuthorizationJobTitleSubtreeQueryReserve(),
            AUTH_JOB_TITLE_SUBTREE_ROW_RESERVE,
            AUTH_JOB_TITLE_SUBTREE_CPU_RESERVE_MS,
            AUTH_JOB_TITLE_SUBTREE_HEAP_RESERVE_BYTES,
            getAuthorizationJobTitleSubtreeMaxVisitedContacts(),
            getAuthorizationJobTitleSubtreeMaxFrontierContacts(),
            JOB_TITLE_AUTH_LIMIT_MESSAGE
        );
    }

    private static void assertJobTitleHierarchyCapacity(
        Integer visitedContactCount,
        Integer frontierContactCount,
        Integer queryReserve,
        Integer rowReserve,
        Integer cpuReserveMs,
        Integer heapReserveBytes,
        Integer maxVisitedContacts,
        Integer maxFrontierContacts,
        String errorMessage
    ) {
        Integer safeVisitedContactCount = visitedContactCount == null ? 0 : visitedContactCount;
        Integer safeFrontierContactCount = frontierContactCount == null ? 0 : frontierContactCount;
        if (safeVisitedContactCount > maxVisitedContacts ||
            safeFrontierContactCount > maxFrontierContacts) {
            throw new CommunicatorException(errorMessage);
        }
        if ((Limits.getLimitQueries() - Limits.getQueries()) <= queryReserve ||
            (Limits.getLimitQueryRows() - Limits.getQueryRows()) <= rowReserve ||
            (Limits.getLimitCpuTime() - Limits.getCpuTime()) <= cpuReserveMs ||
            (Limits.getLimitHeapSize() - Limits.getHeapSize()) <= heapReserveBytes) {
            throw new CommunicatorException(errorMessage);
        }
    }

    private static Integer getPublishJobTitleSubtreeQueryReserve() {
        return publishJobTitleSubtreeQueryReserveOverride != null
            ? publishJobTitleSubtreeQueryReserveOverride
            : PUBLISH_JOB_TITLE_SUBTREE_QUERY_RESERVE;
    }

    private static Integer getPublishJobTitleSubtreeRowReserve() {
        return publishJobTitleSubtreeRowReserveOverride != null
            ? publishJobTitleSubtreeRowReserveOverride
            : PUBLISH_JOB_TITLE_SUBTREE_ROW_RESERVE;
    }

    private static Integer getPublishJobTitleSubtreeMaxVisitedContacts() {
        return publishJobTitleSubtreeMaxVisitedContactsOverride != null
            ? publishJobTitleSubtreeMaxVisitedContactsOverride
            : PUBLISH_JOB_TITLE_SUBTREE_MAX_VISITED_CONTACTS;
    }

    private static Integer getPublishJobTitleSubtreeMaxFrontierContacts() {
        return publishJobTitleSubtreeMaxFrontierContactsOverride != null
            ? publishJobTitleSubtreeMaxFrontierContactsOverride
            : PUBLISH_JOB_TITLE_SUBTREE_MAX_FRONTIER_CONTACTS;
    }

    private static Integer getAuthorizationJobTitleSubtreeQueryReserve() {
        return authorizationJobTitleSubtreeQueryReserveOverride != null
            ? authorizationJobTitleSubtreeQueryReserveOverride
            : AUTH_JOB_TITLE_SUBTREE_QUERY_RESERVE;
    }

    private static Integer getAuthorizationJobTitleSubtreeMaxVisitedContacts() {
        return authorizationJobTitleSubtreeMaxVisitedContactsOverride != null
            ? authorizationJobTitleSubtreeMaxVisitedContactsOverride
            : AUTH_JOB_TITLE_SUBTREE_MAX_VISITED_CONTACTS;
    }

    private static Integer getAuthorizationJobTitleSubtreeMaxFrontierContacts() {
        return authorizationJobTitleSubtreeMaxFrontierContactsOverride != null
            ? authorizationJobTitleSubtreeMaxFrontierContactsOverride
            : AUTH_JOB_TITLE_SUBTREE_MAX_FRONTIER_CONTACTS;
    }

    private static Integer getAuthorizationJobTitleInitialContactMaxContacts() {
        return AUTH_JOB_TITLE_INITIAL_CONTACT_MAX_CONTACTS;
    }

    private static Integer calculatePublishJobTitleSubtreeSafeQueryCapacity(
        Integer visitedContactCount,
        Integer guardFrontierContactCount,
        Integer resultFrontierContactCount
    ) {
        return calculatePublishJobTitleSubtreeSafeQueryCapacity(
            visitedContactCount,
            guardFrontierContactCount,
            resultFrontierContactCount,
            JOB_TITLE_AND_SUBORDINATES_LIMIT_MESSAGE
        );
    }

    private static Integer calculatePublishJobTitleSubtreeSafeQueryCapacity(
        Integer visitedContactCount,
        Integer guardFrontierContactCount,
        Integer resultFrontierContactCount,
        String limitMessage
    ) {
        Integer safeVisitedContactCount = visitedContactCount == null ? 0 : visitedContactCount;
        Integer safeGuardFrontierContactCount =
            guardFrontierContactCount == null ? 0 : guardFrontierContactCount;
        Integer safeResultFrontierContactCount =
            resultFrontierContactCount == null ? 0 : resultFrontierContactCount;
        assertPublishJobTitleHierarchyCapacity(
            safeVisitedContactCount,
            safeGuardFrontierContactCount
        );

        Integer safeCapacity = getRemainingGovernorCapacity(
            Limits.getLimitQueryRows(),
            Limits.getQueryRows(),
            getPublishJobTitleSubtreeRowReserve()
        );
        safeCapacity = Math.min(
            safeCapacity,
            Math.max(0, getPublishJobTitleSubtreeMaxVisitedContacts() - safeVisitedContactCount)
        );
        if (resultFrontierContactCount != null) {
            safeCapacity = Math.min(
                safeCapacity,
                Math.max(0, getPublishJobTitleSubtreeMaxFrontierContacts() - safeResultFrontierContactCount)
            );
        }
        if (safeCapacity <= 0) throw new CommunicatorException(limitMessage);
        return safeCapacity;
    }

    private static Integer getRemainingGovernorCapacity(
        Integer governorLimit,
        Integer usedAmount,
        Integer reserve
    ) {
        Integer safeGovernorLimit = governorLimit == null ? 0 : governorLimit;
        Integer safeUsedAmount = usedAmount == null ? 0 : usedAmount;
        Integer safeReserve = reserve == null ? 0 : reserve;
        Integer remainingCapacity = safeGovernorLimit - safeUsedAmount - safeReserve;
        return remainingCapacity > 0 ? remainingCapacity : 0;
    }

    private static void assertJobTitleContactResultWithinCapacity(
        Integer resultSize,
        Integer safeCapacity,
        String limitMessage
    ) {
        Integer safeResultSize = resultSize == null ? 0 : resultSize;
        Integer validatedCapacity = safeCapacity == null ? 0 : safeCapacity;
        if (validatedCapacity <= 0 || safeResultSize > validatedCapacity) {
            throw new CommunicatorException(limitMessage);
        }
    }

    private static AudienceUserRecord toAudienceUserFromContact(AudienceContactRecord contactRecord) {
        if (contactRecord == null) return null;
        return new AudienceUserRecord(
            contactRecord.usuarioId,
            contactRecord.usuarioIsActive,
            contactRecord.usuarioType,
            contactRecord.usuarioLicenseName,
            contactRecord.usuarioRoleId,
            contactRecord.usuarioSalesCompany,
            contactRecord.contactId,
            contactRecord.cargoId
        );
    }

    private static Integer requirePositiveQueryLimit(Integer limitSize) {
        if (limitSize == null || limitSize <= 0) {
            throw new IllegalArgumentException('The query limit must be positive.');
        }
        return limitSize;
    }

    private static Id parseTargetId(String rawTargetId) {
        if (String.isBlank(rawTargetId)) return null;
        try {
            return (Id) rawTargetId.trim();
        } catch (Exception ex) {
            return null;
        }
    }

    private static Set<Id> ensureRecipientBucket(
        Map<String, Set<Id>> recipientsByAudience,
        String audienceKey
    ) {
        if (!recipientsByAudience.containsKey(audienceKey)) {
            recipientsByAudience.put(audienceKey, new Set<Id>());
        }
        return recipientsByAudience.get(audienceKey);
    }

    private static Set<String> mergeAudienceKeysByContact(
        Map<Id, Set<String>> audienceKeysByContactId,
        Id contactId,
        Set<String> audienceKeys
    ) {
        Set<String> addedAudienceKeys = new Set<String>();
        if (contactId == null || audienceKeys == null || audienceKeys.isEmpty()) {
            return addedAudienceKeys;
        }
        if (!audienceKeysByContactId.containsKey(contactId)) {
            audienceKeysByContactId.put(contactId, new Set<String>());
        }
        Set<String> currentAudienceKeys = audienceKeysByContactId.get(contactId);
        for (String audienceKey : audienceKeys) {
            if (currentAudienceKeys.add(audienceKey)) {
                addedAudienceKeys.add(audienceKey);
            }
        }
        return addedAudienceKeys;
    }

    private static void addAudienceKeys(
        Map<Id, Set<String>> keysByTarget,
        Id targetId,
        Set<String> audienceKeys
    ) {
        if (!keysByTarget.containsKey(targetId)) keysByTarget.put(targetId, new Set<String>());
        keysByTarget.get(targetId).addAll(audienceKeys);
    }

    private static void addAudienceKeys(
        Map<String, Set<String>> keysByTarget,
        String targetId,
        Set<String> audienceKeys
    ) {
        if (!keysByTarget.containsKey(targetId)) keysByTarget.put(targetId, new Set<String>());
        keysByTarget.get(targetId).addAll(audienceKeys);
    }
}