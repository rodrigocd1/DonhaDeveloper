import { LightningElement, api, track } from 'lwc';
import currentUserId           from '@salesforce/user/Id';
import getGroupMembersAsDTO    from '@salesforce/apex/CommunicatorChatController.getGroupMembersAsDTO';
import saveGroupDetails        from '@salesforce/apex/CommunicatorChatController.saveGroupDetails';
import searchSubordinateUsers  from '@salesforce/apex/CommunicatorChatController.searchSubordinateUsers';
import deleteGroupAndMembers   from '@salesforce/apex/CommunicatorChatController.deleteGroupAndMembers';

const DEBOUNCE_MS      = 350;
const MIN_SEARCH_CHARS = 3;

export default class CommunicatorGroupDetailsModal extends LightningElement {

    /** GroupListItemDTO - passed by communicatorHistoryPage */
    @api group = null;

    @track _members            = [];
    @track _pendingRemovals    = [];   // CommunicatorGroupMember__c Ids to delete on save
    @track _pendingAdds        = [];   // { id: UserId, name: UserName } to add on save
    @track _editingName        = false;
    @track _newGroupName       = '';
    @track _isAddingUsersView  = false;
    @track _searchTerm         = '';
    @track _searchResults      = [];
    @track _showDropdown       = false;
    @track _isSearching        = false;
    @track _showDeleteConfirm  = false;
    @track isLoading           = false;
    @track isSaving            = false;

    _currentUserId = currentUserId;
    _debounceTimer = null;
    _blurTimer     = null;

    connectedCallback() {
        this._newGroupName = this.group?.groupName || '';
        this._loadMembers();
    }

    get isAdmin() {
        return this.group?.createdByUserId === this._currentUserId;
    }

    get displayedGroupName() {
        return this._newGroupName || this.group?.groupName || '';
    }

    get displayedMembers() {
        const removals = new Set(this._pendingRemovals);
        return (this._members || [])
            .filter(m => !removals.has(m.memberId))
            .map(m => ({
                memberId: m.memberId,
                userId:   m.userId,
                userName: m.userName,
                isAdmin:  m.userId === this.group?.createdByUserId,
                canRemove: this.isAdmin && m.userId !== this.group?.createdByUserId
            }))
            .sort((a, b) => {
                if (a.isAdmin && !b.isAdmin) return -1;
                if (!a.isAdmin && b.isAdmin) return 1;
                return (a.userName || '').localeCompare(b.userName || '', 'pt-BR');
            });
    }

    get pendingAdds() {
        return this._pendingAdds;
    }

    get hasSearchResults() {
        return this._searchResults.length > 0;
    }

    get isSaveDisabled() {
        return this.isSaving || this.isLoading;
    }

    handleEditName() {
        this._editingName = true;
    }

    handleConfirmName() {
        this._editingName = false;
    }

    handleNameInput(event) {
        this._newGroupName = event.target.value;
    }

    handleRemoveMember(event) {
        const memberId = event.currentTarget.dataset.id;
        if (memberId && !this._pendingRemovals.includes(memberId)) {
            this._pendingRemovals = [...this._pendingRemovals, memberId];
        }
    }

    handleAddUsers() {
        if (!this.isAdmin) return;
        this._isAddingUsersView = true;
    }

    handleBackFromAddUsers() {
        this._isAddingUsersView = false;
        this._searchTerm        = '';
        this._searchResults     = [];
        this._showDropdown      = false;
        this._isSearching       = false;
        clearTimeout(this._debounceTimer);
        clearTimeout(this._blurTimer);
    }

    handleSearchInput(event) {
        const val = event.target.value;
        this._searchTerm = val;
        clearTimeout(this._debounceTimer);

        if (val.trim().length < MIN_SEARCH_CHARS) {
            this._searchResults = [];
            this._showDropdown  = false;
            return;
        }

        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._debounceTimer = setTimeout(() => this._doSearch(val.trim()), DEBOUNCE_MS);
    }

    handleDropdownMousedown(event) {
        // Prevents input blur when clicking/tapping dropdown items (touchpad fix)
        event.preventDefault();
    }

    handleSearchBlur() {
        clearTimeout(this._blurTimer);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._blurTimer = setTimeout(() => {
            this._showDropdown = false;
        }, 300);
    }

    async _doSearch(term) {
        this._isSearching  = true;
        this._showDropdown = true;
        try {
            const data = await searchSubordinateUsers({ keyword: term });
            const activeMemberUserIds = new Set(this.displayedMembers.map(m => m.userId));
            const selectedIds         = new Set((this._pendingAdds || []).map(u => u.id));
            this._searchResults = (data || []).filter(u =>
                !activeMemberUserIds.has(u.id) && !selectedIds.has(u.id)
            );
        } catch (e) {
            this._searchResults = [];
            // eslint-disable-next-line no-console
            console.error('communicatorGroupDetailsModal._doSearch:', e);
        } finally {
            this._isSearching = false;
        }
    }

    handleSelectUser(event) {
        clearTimeout(this._blurTimer);
        const id   = event.currentTarget.dataset.id;
        const name = event.currentTarget.dataset.name;
        if (!id) return;

        const removedExistingMember = (this._members || []).find(
            m => m.userId === id && this._pendingRemovals.includes(m.memberId)
        );

        if (removedExistingMember) {
            this._pendingRemovals = this._pendingRemovals.filter(mid => mid !== removedExistingMember.memberId);
        } else if (!this._pendingAdds.some(u => u.id === id)) {
            this._pendingAdds = [...this._pendingAdds, { id, name }];
        }

        this._searchTerm    = '';
        this._searchResults = [];
        this._showDropdown  = false;
    }

    handleRemovePendingAdd(event) {
        const id = event.currentTarget.dataset.id;
        this._pendingAdds = this._pendingAdds.filter(u => u.id !== id);
    }

    // eslint-disable-next-line no-unused-vars
    handleDeactivateGroup(event) {
        if (!this.isAdmin || !this.group?.groupId) return;
        this._showDeleteConfirm = true;
    }

    handleCancelDeleteGroup() {
        this._showDeleteConfirm = false;
    }

    async handleConfirmDeleteGroup() {
        if (!this.isAdmin || !this.group?.groupId) return;

        this.isSaving = true;
        try {
            await deleteGroupAndMembers({ groupId: this.group.groupId });
            this._showDeleteConfirm = false;
            this.dispatchEvent(new CustomEvent('groupdeleted', {
                detail: { groupId: this.group.groupId }
            }));
        } catch (e) {
            // eslint-disable-next-line no-console
            console.error('communicatorGroupDetailsModal.handleDeactivateGroup:', e);
        } finally {
            this.isSaving = false;
        }
    }

    async handleSave() {
        this.isSaving = true;
        try {
            const newName = (this._newGroupName || '').trim();
            await saveGroupDetails({
                groupId:            this.group.groupId,
                newName:            newName,
                removedMemberIds:   this._pendingRemovals,
                addedMemberUserIds: this._pendingAdds.map(u => u.id)
            });
            this.dispatchEvent(new CustomEvent('groupupdated', {
                detail: {
                    groupId:   this.group.groupId,
                    groupName: newName || this.group.groupName
                }
            }));
        } catch (e) {
            // eslint-disable-next-line no-console
            console.error('communicatorGroupDetailsModal.handleSave:', e);
        } finally {
            this.isSaving = false;
        }
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    async _loadMembers() {
        if (!this.group?.groupId) return;
        this.isLoading = true;
        try {
            const data = await getGroupMembersAsDTO({ groupId: this.group.groupId });
            this._members = data || [];
        } catch (e) {
            // eslint-disable-next-line no-console
            console.error('communicatorGroupDetailsModal._loadMembers:', e);
            this._members = [];
        } finally {
            this.isLoading = false;
        }
    }
}