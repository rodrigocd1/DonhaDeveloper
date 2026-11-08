import { LightningElement, api } from 'lwc';

const VARIANT_EXPANDED = 'expanded';

export default class CommunicatorBroadcastList extends LightningElement {
    _searchKeyword = '';

    @api variant;
    @api items = [];
    @api isLoading = false;
    @api isLoadingMore = false;
    @api hasMore = false;
    @api errorMessage = '';

    @api
    get searchKeyword() {
        return this._searchKeyword;
    }

    set searchKeyword(value) {
        this._searchKeyword = String(value || '');
    }

    handleSelect(event) {
        const groupId = event.currentTarget?.dataset?.groupId;
        if (!groupId) return;
        this.dispatchEvent(new CustomEvent('broadcastselect', {
            detail: { groupId }
        }));
    }

    handleSearchInput(event) {
        this.searchKeyword = String(event?.target?.value || '');
        this.dispatchEvent(new CustomEvent('searchchange', {
            detail: {
                keyword: this.searchKeyword
            }
        }));
    }

    handleSearchKeyDown(event) {
        if (event.key !== 'Escape') return;
        event.preventDefault();
        this.handleClearSearch();
    }

    handleClearSearch() {
        if (!this.hasSearchKeyword) return;
        this.searchKeyword = '';
        this.dispatchEvent(new CustomEvent('clearsearch'));
    }

    handleLoadMore() {
        this.dispatchEvent(new CustomEvent('loadmore'));
    }

    get hasItems() {
        return (this.items || []).length > 0;
    }

    get hasVisibleItems() {
        return this.filteredItems.length > 0;
    }

    get hasSearchKeyword() {
        return this.normalizedSearchKeyword.length > 0;
    }

    get containerClass() {
        return this.variant === VARIANT_EXPANDED
            ? 'comm-broadcast-list comm-broadcast-list--expanded'
            : 'comm-broadcast-list comm-broadcast-list--compact';
    }

    get normalizedSearchKeyword() {
        return String(this.searchKeyword || '').trim().toLowerCase();
    }

    get filteredItems() {
        const keyword = this.normalizedSearchKeyword;
        const sourceItems = Array.isArray(this.items) ? this.items : [];
        if (!keyword) {
            return sourceItems;
        }

        return sourceItems.filter(item => this._matchesSearch(item, keyword));
    }

    get displayItems() {
        return this.filteredItems.map(item => {
            const unreadCount = Math.max(0, Number(item?.unreadCount) || 0);
            const hasPublishedThread = !!item?.threadId;
            const showUnreadMessageText = unreadCount > 0 && hasPublishedThread;
            const unreadMessageText = showUnreadMessageText
                ? (unreadCount === 1 ? '1 nova mensagem' : `${unreadCount > 99 ? '99+' : unreadCount} novas mensagens`)
                : '';
            const unreadMessageAccessibilityLabel = showUnreadMessageText
                ? (unreadCount > 99
                    ? 'Mais de 99 novas mensagens'
                    : unreadCount === 1
                        ? '1 nova mensagem'
                        : `${unreadCount} novas mensagens`)
                : '';
            return {
                ...item,
                unreadCount,
                unreadAccessibleLabel: unreadCount > 99
                    ? 'Mais de 99 mensagens não lidas'
                    : unreadCount === 1
                        ? '1 mensagem não lida'
                        : `${unreadCount} mensagens não lidas`,
                showUnreadMessageText,
                unreadMessageText,
                unreadMessageAccessibilityLabel
            };
        });
    }

    get emptyContainerClass() {
        const classes = ['comm-broadcast-list__empty'];
        if (this.hasSearchKeyword) {
            classes.push('comm-broadcast-list__empty--search');
        }
        return classes.join(' ');
    }

    get emptyMessage() {
        return this.hasSearchKeyword
            ? 'Nenhum comunicado encontrado para a busca.'
            : 'Nenhum comunicado disponivel no momento.';
    }

    _matchesSearch(item, keyword) {
        const searchableText = [
            item?.groupName,
            item?.description,
            item?.createdByUserName
        ]
            .map(value => this._normalizeText(value))
            .filter(value => !!value)
            .join(' ');

        return searchableText.includes(keyword);
    }

    _normalizeText(value) {
        return String(value || '').trim().toLowerCase();
    }
}