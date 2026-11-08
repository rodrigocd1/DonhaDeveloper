import { loadScript } from 'lightning/platformResourceLoader';
import SOCKETIO_V2 from '@salesforce/resourceUrl/communicatorSocketio';
import USER_ID from '@salesforce/user/Id';
import COMMUNICATOR_SOCKET_HEROKU_URL from '@salesforce/label/c.CommunicatorSocketHerokuUrl';

const SERVER_URL = String(COMMUNICATOR_SOCKET_HEROKU_URL || '').trim();

// Estado singleton — compartilhado por todos os consumidores no mesmo contexto de módulo
let socket = null;
let libLoadedPromise = null;
let listeners = new Map(); // Map<eventName, Set<Function>>
let refCount = 0;

function normalizePresenceUserId(value) {
    const rawValue = String(value || '').trim();
    return rawValue ? rawValue.substring(0, 15).toUpperCase() : '';
}

function normalizePresenceUserId18(value) {
    const rawValue = String(value || '').trim();
    return rawValue.length === 18 ? rawValue : '';
}

function isSalesforceUserId(value) {
    return /^005[A-Za-z0-9]{12}([A-Za-z0-9]{3})?$/.test(String(value || '').trim());
}

function isOnlinePresenceKeyword(value) {
    const normalizedValue = String(value || '').toLowerCase();
    return ['online', 'connected', 'active', 'available', 'true', '1'].includes(normalizedValue);
}

function resolvePresenceConnectionState(value, assumeOnlineWhenNoSignal = false) {
    if (typeof value === 'boolean') return value;
    if (typeof value === 'number') return value > 0;
    if (typeof value === 'string') return isOnlinePresenceKeyword(value);
    if (!value || typeof value !== 'object') return false;
    if (typeof value.connections === 'number') return value.connections > 0;
    if (typeof value.connectionCount === 'number') return value.connectionCount > 0;
    if (typeof value.connected === 'boolean') return value.connected;
    if (typeof value.isOnline === 'boolean') return value.isOnline;
    if (typeof value.online === 'boolean') return value.online;
    if (isOnlinePresenceKeyword(value.status)) return true;
    if (isOnlinePresenceKeyword(value.connectionStatus)) return true;
    if (isOnlinePresenceKeyword(value.state)) return true;
    if (isOnlinePresenceKeyword(value.socketStatus)) return true;
    if (value.socketId || value.socket_id || value.sid) return true;
    if (assumeOnlineWhenNoSignal) return true;
    return false;
}

function resolvePresenceUserId(entry) {
    if (!entry || typeof entry !== 'object') return '';
    const candidates = [
        entry.userId, entry.user_id, entry.id, entry.Id, entry.user,
        entry.sfUserId, entry.sf_user_id, entry.salesforceId, entry.salesforce_id,
        entry.participantId, entry.participant_id, entry.contactId, entry.contact_id,
        entry.username, entry.login
    ];
    for (const candidateId of candidates) {
        const caseSensitive18 = normalizePresenceUserId18(candidateId);
        if (caseSensitive18) return caseSensitive18;
    }
    for (const candidateId of candidates) {
        const normalizedUserId = normalizePresenceUserId(candidateId);
        if (normalizedUserId) return normalizedUserId;
    }
    return '';
}

function resolvePresenceUserIdRaw(entry) {
    if (!entry || typeof entry !== 'object') return '';
    const candidates = [
        entry.userId, entry.user_id, entry.id, entry.Id, entry.user,
        entry.sfUserId, entry.sf_user_id, entry.salesforceId, entry.salesforce_id,
        entry.participantId, entry.participant_id, entry.contactId, entry.contact_id,
        entry.username, entry.login
    ];
    for (const candidateId of candidates) {
        const rawValue = String(candidateId || '').trim();
        if (rawValue) return rawValue;
    }
    return '';
}

function normalizePresenceArrayItems(items) {
    return (items || []).map(item => {
        if (item && typeof item === 'object') return item;
        if (typeof item === 'string' || typeof item === 'number') {
            return { userId: String(item), status: 'online' };
        }
        return null;
    }).filter(Boolean);
}

function extractPresenceEntries(response) {
    if (!response) return [];
    if (Array.isArray(response)) return normalizePresenceArrayItems(response);
    if (typeof response !== 'object') return [];

    const directArrays = [
        response.users, response.onlineUsers, response.participants, response.connections,
        response.statuses, response?.data?.users, response?.payload?.users, response?.result?.users
    ].filter(Array.isArray);
    if (directArrays.length > 0) return normalizePresenceArrayItems(directArrays.flat());

    const entries = [];
    Object.entries(response).forEach(([key, value]) => {
        if (Array.isArray(value)) {
            if (isSalesforceUserId(key)) {
                if (value.length === 0) {
                    entries.push({ userId: key, connections: 0 });
                    return;
                }
                value.forEach(item => {
                    if (item && typeof item === 'object') {
                        if (resolvePresenceUserId(item)) {
                            entries.push(item);
                            return;
                        }
                        entries.push({ ...item, userId: key, connections: value.length });
                        return;
                    }
                    entries.push({
                        userId: key,
                        socketId: String(item || ''),
                        connections: value.length,
                        status: 'online'
                    });
                });
                return;
            }
            entries.push(...normalizePresenceArrayItems(value));
            return;
        }
        if (value && typeof value === 'object') {
            if (resolvePresenceUserId(value)) entries.push(value);
            else if (isSalesforceUserId(key)) entries.push({ ...value, userId: key });
            return;
        }
        if (isSalesforceUserId(key)) entries.push({ userId: key, status: value });
    });
    return entries;
}

function summarizePresenceLookup(requestedUserIds, response) {
    const requestedRawIds = [...new Set(
        (requestedUserIds || [])
            .map(userId => String(userId || '').trim())
            .filter(Boolean)
    )];
    const normalizedRequestedIds = [...new Set(
        requestedRawIds
            .map(userId => normalizePresenceUserId(userId))
            .filter(Boolean)
    )];
    const onlineUserIds = [];
    const onlineUserIdsRaw = [];
    const seenIds = new Set();
    extractPresenceEntries(response).forEach(entry => {
        const userId = resolvePresenceUserId(entry);
        if (!userId || seenIds.has(userId)) return;
        if (resolvePresenceConnectionState(entry, true)) {
            seenIds.add(userId);
            onlineUserIds.push(userId);
            const rawUserId = resolvePresenceUserIdRaw(entry);
            if (rawUserId) onlineUserIdsRaw.push(rawUserId);
        }
    });
    return {
        totalConsultados: requestedRawIds.length,
        usuariosConsultados: requestedRawIds,
        usuariosConsultadosNormalizados15: normalizedRequestedIds,
        totalOnline: onlineUserIds.length,
        usuariosOnline: onlineUserIdsRaw,
        usuariosOnlineNormalizados15: onlineUserIds
    };
}

function gerarMessageId() {
    return `msg_${Date.now()}_${Math.random().toString(36).slice(2, 10)}`;
}

// Carrega a lib socket.io uma única vez; permite retry se a Promise anterior falhou
function ensureLibLoaded(host) {
    if (!libLoadedPromise) {
        libLoadedPromise = loadScript(host, SOCKETIO_V2).catch(err => {
            libLoadedPromise = null;
            return Promise.reject(err);
        });
    }
    return libLoadedPromise;
}

// Re-registra listeners do Map no socket — chamado após reconexão
function reregistrarListeners() {
    if (!socket) return;
    listeners.forEach((callbacks, eventName) => {
        callbacks.forEach(cb => socket.on(eventName, cb));
    });
}

function resolveServerUrl() {
    if (!SERVER_URL) {
        throw new Error('[Comunicador] URL do socket não configurada (Custom Label CommunicatorSocketHerokuUrl).');
    }
    return SERVER_URL.endsWith('/') ? SERVER_URL : `${SERVER_URL}/`;
}

export async function connect(host, opts = {}) {
    if (socket && socket.connected) return Promise.resolve();

    const origin = opts.origin || (window.location.pathname.startsWith('/s/') ? 'experience' : 'lex');

    await ensureLibLoaded(host);

    return new Promise((resolve, reject) => {
        const serverUrl = resolveServerUrl();
        // eslint-disable-next-line no-undef
        socket = io(serverUrl, {
            query: { userId: USER_ID, url: window.location.origin, origin },
            transports: ['websocket'],
            forceNew: true,
            reconnection: true,
            reconnectionAttempts: 10,
            reconnectionDelay: 1500
        });

        function onConnect() {
            socket.off('connect_error', onConnectError);
            console.log('[Comunicador] Socket conectado');
            resolve();
        }

        function onConnectError(err) {
            socket.off('connect', onConnect);
            console.error('[Comunicador] Erro de conexão inicial', err);
            reject(err);
        }

        socket.once('connect', onConnect);
        socket.once('connect_error', onConnectError);

        // Auto-ack: confirma entrega de cada mensagem recebida
        socket.on('receivedMessage', (msg) => {
            const messageId = msg.messageId || msg.message_id;
            if (messageId) {
                socket.emit('messageDelivered', { messageId, userId: USER_ID, origin });
            }
        });

        // Re-registra listeners externos após reconexão automática
        socket.on('reconnect', () => {
            console.log('[Comunicador] Socket reconectado — re-registrando listeners');
            reregistrarListeners();
        });
    });
}

export function disconnect() {
    if (socket) {
        socket.disconnect();
        socket = null;
        console.log('[Comunicador] Socket desconectado');
    }
    listeners = new Map();
    refCount = 0;
}

export function acquire() {
    refCount++;
    console.log(`[Comunicador] acquire — refCount: ${refCount}`);
}

export function release() {
    refCount--;
    console.log(`[Comunicador] release — refCount: ${refCount}`);
    if (refCount <= 0) {
        disconnect();
    }
}

export function sendMessage(message, userIds) {
    return new Promise((resolve, reject) => {
        if (!socket || !socket.connected) {
            reject(new Error('[Comunicador] Socket não conectado'));
            return;
        }
        const messageId = gerarMessageId();
        socket.emit('sendMessage', { messageId, message, userIds }, (ack) => resolve(ack));
    });
}

export function getUsersConnectionStatus(userIds) {
    return new Promise((resolve, reject) => {
        if (!socket || !socket.connected) {
            reject(new Error('[Comunicador] Socket não conectado'));
            return;
        }
        const requestedUserIds = [...new Set(
            (userIds || [])
                .map(userId => String(userId || '').trim())
                .filter(Boolean)
        )];
        console.log('[Comunicador][Presence] Consultando usuarios no socket', {
            totalConsultados: requestedUserIds.length,
            usuariosConsultados: requestedUserIds
        });
        socket.emit('getUsersConnectionStatus', { userIds: requestedUserIds }, (response) => {
            console.log(
                '[Comunicador][Presence] Resultado da consulta no socket',
                summarizePresenceLookup(requestedUserIds, response)
            );
            console.log('[Comunicador][Presence] Resposta bruta do socket', response);
            resolve(response);
        });
    });
}

export function on(eventName, callback) {
    if (!listeners.has(eventName)) {
        listeners.set(eventName, new Set());
    }
    listeners.get(eventName).add(callback);

    if (socket) {
        socket.on(eventName, callback);
    }

    // Retorna função de unsubscribe
    return () => {
        if (listeners.has(eventName)) {
            listeners.get(eventName).delete(callback);
        }
        if (socket) {
            socket.off(eventName, callback);
        }
    };
}

export function isConnected() {
    return !!(socket && socket.connected);
}