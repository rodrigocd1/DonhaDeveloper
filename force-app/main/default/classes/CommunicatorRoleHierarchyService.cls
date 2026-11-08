/**
 * @description Shared bulk resolver for Salesforce role hierarchy descendants.
 */
public with sharing class CommunicatorRoleHierarchyService {

    public static Map<Id, Set<Id>> getRoleAndDescendantIdsByRoot(Set<Id> rootRoleIds) {
        if (rootRoleIds == null || rootRoleIds.isEmpty()) {
            return new Map<Id, Set<Id>>();
        }
        return resolveRoleAndDescendantIdsByRoot(
            rootRoleIds,
            [SELECT Id, ParentRoleId FROM UserRole]
        );
    }

    public static Set<Id> getTraditionalGroupEligibleRoleIds(Id currentUserRoleId) {
        if (currentUserRoleId == null) {
            return new Set<Id>();
        }
        return resolveTraditionalGroupEligibleRoleIds(
            currentUserRoleId,
            [SELECT Id, ParentRoleId FROM UserRole]
        );
    }

    @TestVisible
    private static Map<Id, Set<Id>> resolveRoleAndDescendantIdsByRoot(
        Set<Id> rootRoleIds,
        List<UserRole> allRoles
    ) {
        Map<Id, Set<Id>> result = new Map<Id, Set<Id>>();
        if (rootRoleIds == null || rootRoleIds.isEmpty()) return result;

        Set<Id> existingRoleIds = new Set<Id>();
        Map<Id, Set<Id>> childrenByParent = new Map<Id, Set<Id>>();
        for (UserRole roleRecord : allRoles) {
            existingRoleIds.add(roleRecord.Id);
            if (roleRecord.ParentRoleId == null) continue;
            if (!childrenByParent.containsKey(roleRecord.ParentRoleId)) {
                childrenByParent.put(roleRecord.ParentRoleId, new Set<Id>());
            }
            childrenByParent.get(roleRecord.ParentRoleId).add(roleRecord.Id);
        }

        for (Id rootRoleId : rootRoleIds) {
            if (rootRoleId == null || !existingRoleIds.contains(rootRoleId)) continue;

            Set<Id> resolved = new Set<Id>{ rootRoleId };
            Set<Id> frontier = new Set<Id>{ rootRoleId };
            while (!frontier.isEmpty()) {
                Set<Id> next = new Set<Id>();
                for (Id roleId : frontier) {
                    Set<Id> children = childrenByParent.get(roleId);
                    if (children == null) continue;
                    for (Id childRoleId : children) {
                        if (resolved.add(childRoleId)) next.add(childRoleId);
                    }
                }
                frontier = next;
            }
            result.put(rootRoleId, resolved);
        }
        return result;
    }

    @TestVisible
    private static Set<Id> resolveTraditionalGroupEligibleRoleIds(
        Id currentUserRoleId,
        List<UserRole> allRoles
    ) {
        Set<Id> result = new Set<Id>();
        if (currentUserRoleId == null || allRoles == null || allRoles.isEmpty()) {
            return result;
        }

        Map<Id, UserRole> rolesById = new Map<Id, UserRole>();
        for (UserRole roleRecord : allRoles) {
            rolesById.put(roleRecord.Id, roleRecord);
        }

        UserRole currentRole = rolesById.get(currentUserRoleId);
        if (currentRole == null) {
            return result;
        }

        Map<Id, Set<Id>> descendantRolesByRoot = resolveRoleAndDescendantIdsByRoot(
            new Set<Id>{ currentUserRoleId },
            allRoles
        );
        if (descendantRolesByRoot.containsKey(currentUserRoleId)) {
            result.addAll(descendantRolesByRoot.get(currentUserRoleId));
        }
        result.remove(currentUserRoleId);

        result.add(currentUserRoleId);

        if (currentRole.ParentRoleId == null) {
            return result;
        }

        result.add(currentRole.ParentRoleId);
        for (UserRole roleRecord : allRoles) {
            if (roleRecord.ParentRoleId == currentRole.ParentRoleId) {
                result.add(roleRecord.Id);
            }
        }

        return result;
    }
}