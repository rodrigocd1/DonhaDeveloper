import { LightningElement, track } from 'lwc';
import currentUserId          from '@salesforce/user/Id';
import searchSubordinateUsers from '@salesforce/apex/CommunicatorChatController.searchSubordinateUsers';
import createGroupWithMembers from '@salesforce/apex/CommunicatorChatController.createGroupWithMembers';
import getCurrentUserName     from '@salesforce/apex/CommunicatorChatController.getCurrentUserName';

const DEBOUNCE_MS       = 350;
const MIN_SEARCH_CHARS  = 3;

export default class CommunicatorCreateGroupModal extends LightningElement {

    @track groupName     = '';
    @track searchTerm    = '';
    @track searchResults = [];
    @track selectedUsers = [];
    @track isSearching   = false;
    @track isSaving      = false;
    @track showDropdown  = false;
    @track nameError     = false;

    _debounceTimer = null;
    _blurTimer     = null;

    // ─────────────────────────────────────────
    // Lifecycle
    // ─────────────────────────────────────────

    async connectedCallback() {
        try {
            const name = await getCurrentUserName();
            this.selectedUsers = [{ id: currentUserId, name, isAdmin: true }];
        } catch (e) {
            console.error('communicatorCreateGroupModal.connectedCallback:', e);
        }
    }

    // ─────────────────────────────────────────
    // Computed
    // ─────────────────────────────────────────

    get nameInputClass() {
        return this.nameError
            ? 'cgm-input cgm-input--error'
            : 'cgm-input';
    }

    get hasResults() {
        return this.searchResults.length > 0;
    }

    get isSaveDisabled() {
        return this.isSaving || !this.groupName.trim();
    }

    // ─────────────────────────────────────────
    // Handlers — name
    // ─────────────────────────────────────────

    handleNameInput(event) {
        this.groupName = event.target.value;
        this.nameError = false;
    }

    // ─────────────────────────────────────────
    // Handlers — user search
    // ─────────────────────────────────────────

    handleSearchInput(event) {
        const val = event.target.value;
        this.searchTerm = val;
        clearTimeout(this._debounceTimer);

        if (val.trim().length < MIN_SEARCH_CHARS) {
            this.searchResults = [];
            this.showDropdown  = false;
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
            this.showDropdown = false;
        }, 300);
    }

    async _doSearch(term) {
        this.isSearching = true;
        this.showDropdown = true;
        try {
            const data = await searchSubordinateUsers({ keyword: term });
            const selectedIds = new Set(this.selectedUsers.map(u => u.id));
            this.searchResults = (data || []).filter(u => !selectedIds.has(u.id) && u.id !== currentUserId);
        } catch (e) {
            this.searchResults = [];
            console.error('communicatorCreateGroupModal._doSearch:', e);
        } finally {
            this.isSearching = false;
        }
    }

    handleSelectUser(event) {
        clearTimeout(this._blurTimer);
        const id   = event.currentTarget.dataset.id;
        const name = event.currentTarget.dataset.name;
        if (!id || this.selectedUsers.some(u => u.id === id)) return;

        this.selectedUsers = [...this.selectedUsers, { id, name }];
        this.searchTerm    = '';
        this.searchResults = [];
        this.showDropdown  = false;
    }

    handleRemoveUser(event) {
        const id = event.currentTarget.dataset.id;
        this.selectedUsers = this.selectedUsers.filter(u => u.id !== id || u.isAdmin);
    }

    // ─────────────────────────────────────────
    // Handlers — save / close
    // ─────────────────────────────────────────

    async handleSave() {
        this.nameError = false;
        if (!this.groupName.trim()) {
            this.nameError = true;
            return;
        }

        this.isSaving = true;
        try {
            await createGroupWithMembers({
                name:      this.groupName.trim(),
                memberIds: this.selectedUsers.map(u => u.id)
            });
            this.dispatchEvent(new CustomEvent('groupcreated'));
        } catch (e) {
            console.error('communicatorCreateGroupModal.handleSave:', e);
        } finally {
            this.isSaving = false;
        }
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }
}