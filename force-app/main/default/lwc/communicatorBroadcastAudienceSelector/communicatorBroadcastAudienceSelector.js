import { LightningElement, api, track } from 'lwc';
import searchBroadcastAudienceTargets from '@salesforce/apex/CommunicatorChatController.searchBroadcastAudienceTargets';

const DEBOUNCE_MS = 300;
const MIN_SEARCH_CHARS = 2;
const SEARCH_LIMIT = 8;
const AUDIENCE_CHANGE_EVENT = 'audiencechange';
const TYPE_ALL_SUPPORTED_USERS = 'AllSupportedUsers';
const ALL_SUPPORTED_USERS_TARGET_NAME = 'Todos os usuários';
const ALL_SUPPORTED_USERS_LOCAL_KEY = 'ALL_SUPPORTED_USERS';

const AUDIENCE_TYPES = [
    { value: 'DirectUser', label: 'Usuários' },
    { value: 'Role', label: 'Papéis' },
    { value: 'RoleAndSubordinatesInternal', label: 'Hierarquia interna' },
    { value: 'RoleAndSubordinatesPortal', label: 'Hierarquia portal' },
    { value: 'RoleAndSubordinatesInternalAndPortal', label: 'Hierarquia e portal' },
    { value: 'PublicGroup', label: 'Grupos públicos' },
    { value: 'SalesCompany', label: 'Empresa de Vendas' },
    { value: 'JobTitle', label: 'Cargo' },
    { value: 'JobTitleAndSubordinates', label: 'Cargo e subordinados' },
    { value: TYPE_ALL_SUPPORTED_USERS, label: 'Todos os usuários' }
];

export default class CommunicatorBroadcastAudienceSelector extends LightningElement {
    _value = [];
    _debounceTimer = null;
    _blurTimer = null;
    _searchVersion = 0;

    @track activeAudienceType = 'DirectUser';
    @track searchKeyword = '';
    @track searchResults = [];
    @track isSearching = false;
    @track dropdownOpen = false;
    @track searchErrorMessage = '';

    @api disabled = false;

    @api
    get value() {
        return this._value;
    }

    set value(nextValue) {
        this._value = this._normalizeCriteriaList(nextValue);
    }

    connectedCallback() {
        if (!this.activeAudienceType) {
            this.activeAudienceType = 'DirectUser';
        }
    }

    disconnectedCallback() {
        clearTimeout(this._debounceTimer);
        clearTimeout(this._blurTimer);
        this._searchVersion += 1;
    }

    get audienceTypeOptions() {
        return AUDIENCE_TYPES.map(option => ({
            ...option,
            isActive: option.value === this.activeAudienceType,
            className: option.value === this.activeAudienceType
                ? 'comm-broadcast-audience-selector__type comm-broadcast-audience-selector__type--active'
                : 'comm-broadcast-audience-selector__type'
        }));
    }

    get hasSelections() {
        return this.selectedCriteria.length > 0;
    }

    get selectedCriteria() {
        return (this._value || []).map((item, index) => ({
            ...item,
            localKey: this._buildCriterionKey(item),
            displayIndex: index + 1,
            typeLabel: this._labelForType(item.AudienceType__c),
            targetName: item.TargetName__c || this._defaultTargetName(item.AudienceType__c)
        }));
    }

    get hasSearchResults() {
        return this.searchResults.length > 0;
    }

    get searchPlaceholder() {
        if (this.activeAudienceType === TYPE_ALL_SUPPORTED_USERS) {
            return 'Adicionar todos os usuários';
        }
        return `Buscar ${this._labelForType(this.activeAudienceType).toLowerCase()}`;
    }

    get showSearchInput() {
        return this.activeAudienceType !== TYPE_ALL_SUPPORTED_USERS;
    }

    get allSupportedUsersHelperText() {
        return 'Inclui todos os usuários ativos suportados pelo comunicador.';
    }

    get emptySelectedMessage() {
        return 'Nenhum usuário válido adicionado.';
    }

    handleAudienceTypeSelect(event) {
        if (this.disabled) return;
        const audienceType = event.currentTarget?.dataset?.type;
        if (!audienceType || audienceType === this.activeAudienceType) return;
        this.activeAudienceType = audienceType;
        if (audienceType === TYPE_ALL_SUPPORTED_USERS) {
            this._ensureAllSupportedUsersCriterion();
        }
        this._resetSearchState({ resetKeyword: true });
    }

    handleSearchInput(event) {
        if (this.disabled || this.activeAudienceType === TYPE_ALL_SUPPORTED_USERS) return;
        const value = String(event?.detail?.value ?? event?.target?.value ?? '');
        this.searchKeyword = value;
        this.searchErrorMessage = '';
        clearTimeout(this._debounceTimer);
        this._searchVersion += 1;
        const searchVersion = this._searchVersion;
        const normalizedValue = value.trim();

        if (normalizedValue.length < MIN_SEARCH_CHARS) {
            this._resetSearchState();
            return;
        }

        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._debounceTimer = setTimeout(() => {
            this._doSearch(normalizedValue, searchVersion);
        }, DEBOUNCE_MS);
    }

    handleSearchBlur() {
        clearTimeout(this._blurTimer);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._blurTimer = setTimeout(() => {
            this.dropdownOpen = false;
        }, 250);
    }

    handleDropdownMousedown(event) {
        event.preventDefault();
    }

    handleClearSearch() {
        this._resetSearchState({ resetKeyword: true });
    }

    handleSelectResult(event) {
        if (this.disabled) return;
        clearTimeout(this._blurTimer);

        const targetId = String(event.currentTarget?.dataset?.id || '').trim();
        const targetName = String(event.currentTarget?.dataset?.name || '').trim();
        if (!targetId || !targetName) return;

        const criterionKey = `${this.activeAudienceType}|${targetId}`;
        if (this._value.some(item => this._buildCriterionKey(item) === criterionKey)) {
            this._resetSearchState({ resetKeyword: true });
            return;
        }

        const nextValue = [
            ...this._value,
            {
                AudienceType__c: this.activeAudienceType,
                TargetId__c: targetId,
                TargetName__c: targetName,
                SortOrder__c: this._value.length + 1,
                IsActive__c: true
            }
        ];
        this._setValue(nextValue);
        this._resetSearchState({ resetKeyword: true });
    }

    handleRemoveCriterion(event) {
        if (this.disabled) return;
        const key = String(event.currentTarget?.dataset?.key || '').trim();
        if (!key) return;

        const nextValue = this._value
            .filter(item => this._buildCriterionKey(item) !== key)
            .map((item, index) => ({
                ...item,
                SortOrder__c: index + 1
            }));
        this._setValue(nextValue);
    }

    async _doSearch(term, searchVersion) {
        if (this.disabled || !term || searchVersion !== this._searchVersion) return;
        this.isSearching = true;
        this.dropdownOpen = true;
        try {
            const results = await searchBroadcastAudienceTargets({
                audienceType: this.activeAudienceType,
                keyword: term,
                limitSize: SEARCH_LIMIT
            });
            if (searchVersion !== this._searchVersion) return;
            const selectedKeys = new Set(this._value.map(item => this._buildCriterionKey(item)));
            this.searchResults = (results || []).filter(result => {
                const key = `${this.activeAudienceType}|${String(result?.id || '').trim()}`;
                return !!result?.id && !selectedKeys.has(key);
            });
        } catch (error) {
            if (searchVersion !== this._searchVersion) return;
            this.searchResults = [];
            this.searchErrorMessage = this._normalizeError(error) || 'Não foi possível pesquisar a audiência.';
        } finally {
            if (searchVersion === this._searchVersion) {
                this.isSearching = false;
            }
        }
    }

    _setValue(nextValue) {
        this._value = this._normalizeCriteriaList(nextValue);
        this.dispatchEvent(new CustomEvent(AUDIENCE_CHANGE_EVENT, {
            detail: { value: [...this._value] }
        }));
    }

    _resetSearchState(options = {}) {
        const { resetKeyword = false } = options || {};
        clearTimeout(this._debounceTimer);
        clearTimeout(this._blurTimer);
        this._searchVersion += 1;
        this.searchResults = [];
        this.isSearching = false;
        this.dropdownOpen = false;
        this.searchErrorMessage = '';
        if (resetKeyword) {
            this.searchKeyword = '';
        }
    }

    _normalizeCriteriaList(value) {
        const source = Array.isArray(value) ? value : [];
        const normalized = [];
        source.forEach((item, index) => {
            const audienceType = String(item?.AudienceType__c || '').trim();
            const targetId = String(item?.TargetId__c || '').trim();
            if (!audienceType) return;
            if (!targetId && audienceType !== TYPE_ALL_SUPPORTED_USERS) return;
            normalized.push({
                AudienceType__c: audienceType,
                TargetId__c: targetId,
                TargetName__c: String(item?.TargetName__c || '').trim()
                    || this._defaultTargetName(audienceType),
                SortOrder__c: Number.isFinite(Number(item?.SortOrder__c)) && Number(item?.SortOrder__c) > 0
                    ? Number(item.SortOrder__c)
                    : index + 1,
                IsActive__c: item?.IsActive__c !== false
            });
        });
        return normalized;
    }

    _buildCriterionKey(item) {
        const audienceType = String(item?.AudienceType__c || '').trim();
        const targetId = String(item?.TargetId__c || '').trim();
        return `${audienceType}|${targetId || (audienceType === TYPE_ALL_SUPPORTED_USERS ? ALL_SUPPORTED_USERS_LOCAL_KEY : '')}`;
    }

    _labelForType(type) {
        return AUDIENCE_TYPES.find(option => option.value === type)?.label || 'Audiência';
    }

    _defaultTargetName(audienceType) {
        return audienceType === TYPE_ALL_SUPPORTED_USERS
            ? ALL_SUPPORTED_USERS_TARGET_NAME
            : 'Alvo sem nome';
    }

    _ensureAllSupportedUsersCriterion() {
        const criterionKey = `${TYPE_ALL_SUPPORTED_USERS}|${ALL_SUPPORTED_USERS_LOCAL_KEY}`;
        if (this._value.some(item => this._buildCriterionKey(item) === criterionKey)) {
            return;
        }
        this._setValue([
            ...this._value,
            {
                AudienceType__c: TYPE_ALL_SUPPORTED_USERS,
                TargetId__c: '',
                TargetName__c: ALL_SUPPORTED_USERS_TARGET_NAME,
                SortOrder__c: this._value.length + 1,
                IsActive__c: true
            }
        ]);
    }

    _normalizeError(error) {
        return String(
            error?.body?.message
            || error?.message
            || error?.statusText
            || ''
        ).trim();
    }
}