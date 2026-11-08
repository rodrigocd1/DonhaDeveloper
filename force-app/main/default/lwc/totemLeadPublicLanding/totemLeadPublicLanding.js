import { LightningElement, api } from 'lwc';
import TOTEM_FILES from '@salesforce/resourceUrl/TotemFiles';
import getPublicConfig from '@salesforce/apex/TotemLeadPublicController.getPublicConfig';
import requestCode from '@salesforce/apex/TotemLeadPublicController.requestCode';
import getDeliveryStatus from '@salesforce/apex/TotemLeadPublicController.getDeliveryStatus';
import retryDelivery from '@salesforce/apex/TotemLeadPublicController.retryDelivery';
import validateCode from '@salesforce/apex/TotemLeadPublicController.validateCode';

const DEFAULT_CONTENT = {
    brandName: 'VEO Energia',
    heroTitle: 'Descubra sua Economia.',
    heroSubtitle: 'Quanto você pode economizar na sua conta de energia?',
    heroTimeText: 'Responda em menos de 30 segundos.',
    primaryButtonLabel: 'Simular Economia',
    simulationTitle: 'Simulação Rápida.',
    resultButtonLabel: 'Ver Resultado',
    resultTitle: 'Você pode economizar até',
    resultMessage: 'por mês com a VEO',
    formTitle: 'Receba sua simulação completa:',
    submitButtonLabel: 'Receber código por e-mail',
    submittingLabel: 'Enviando...',
    reasonsLabel: 'Por que a VEO?',
    successTitle: 'Código enviado!',
    codeSentMessage: 'Enviamos o código para o e-mail informado.',
    validationSuccessMessage: 'Dados validados. Você já pode retirar seu brinde!',
    giftNotice: 'Ganhe um BRINDE EXCLUSIVO ao participar!',
    giftInputLabel: 'Digite seu código exclusivo',
    giftInputPlaceholder: 'Ex: VEO-12345',
    giftButtonLabel: 'Validar código',
    secondaryButtonLabel: 'Reiniciar',
    footerText: 'veoenergia.com.br',
    benefits: ['Sem obras ou instalação', 'Energia 100% renovável', 'Economia garantida em contrato']
};

const HEX_COLOR_REGEX = /^#[0-9A-F]{6}$/i;
const MAX_POLL_ATTEMPTS = 12;
const POLL_INTERVAL_MS = 1500;

export default class TotemLeadPublicLanding extends LightningElement {
    @api configurationKey = 'VEO';

    // Propriedades legadas mantidas apenas por compatibilidade com a instância
    // já publicada no Experience Builder. A jornada usa somente configurationKey.
    @api brandName;
    @api partnerName;
    @api primaryLogoUrl;
    @api partnerLogoUrl;
    @api backgroundImageUrl;
    @api promoImageUrl;
    @api giftImageUrl;
    @api primaryColor;
    @api secondaryColor;
    @api accentColor;
    @api textColor;
    @api surfaceColor;
    @api heroTitle;
    @api heroSubtitle;
    @api heroTimeText;
    @api primaryButtonLabel;
    @api resultButtonLabel;
    @api submitButtonLabel;
    @api submittingLabel;
    @api secondaryButtonLabel;
    @api reasonsLabel;
    @api simulationLabel;
    @api successTitle;
    @api successMessage;
    @api benefitsText;
    @api giftNotice;
    @api giftInputLabel;
    @api giftInputPlaceholder;
    @api giftButtonLabel;
    @api footerText;
    @api leadSource;
    @api leadOrigin;
    @api formWeb;
    @api partnerCode;
    @api campaignCode;
    @api pageIdentifier;
    @api showDevControls;

    config;
    currentStep = 1;
    answers = {};
    formData = { fullName: '', cpf: '', mobilePhone: '', email: '', consentAccepted: false };
    giftCode = '';
    errorMessage = '';
    statusMessage = '';
    isLoading = true;
    isSubmitting = false;
    isCheckingDelivery = false;
    isValidating = false;
    canRetryDelivery = false;
    deliveryReady = false;
    isBlocked = false;
    isValidated = false;
    requestId;
    accessToken;
    pollAttempts = 0;
    pollTimer;

    connectedCallback() {
        this.loadConfig();
    }

    disconnectedCallback() {
        this.clearPollTimer();
    }

    async loadConfig() {
        this.isLoading = true;
        this.errorMessage = '';
        try {
            this.config = await getPublicConfig({ configurationKey: this.configurationKey });
            await this.restoreSession();
        } catch (error) {
            this.errorMessage = this.errorText(error, 'Configuração indisponível no momento.');
        } finally {
            this.isLoading = false;
        }
    }

    get isStep1() {
        return !this.isLoading && Boolean(this.config) && this.currentStep === 1;
    }

    get isStep2() {
        return !this.isLoading && Boolean(this.config) && this.currentStep === 2;
    }

    get isStep3() {
        return !this.isLoading && Boolean(this.config) && this.currentStep === 3;
    }

    get isStep4() {
        return !this.isLoading && Boolean(this.config) && this.currentStep === 4;
    }

    get content() {
        return { ...DEFAULT_CONTENT, ...(this.config?.content || {}) };
    }

    get resolvedBrandName() {
        return this.content.brandName;
    }

    get logoUrl() {
        return this.resolveAsset(this.config?.logoPath, `${TOTEM_FILES}/logo_white.png`);
    }

    get heroPhotoStyle() {
        const imageUrl = this.resolveAsset(
            this.config?.backgroundImagePath,
            `${TOTEM_FILES}/background_totem_leads_JPG.JPG`
        );
        return `background-image: linear-gradient(180deg, rgba(8, 48, 80, 0.06) 0%, rgba(8, 48, 80, 0.18) 48%, rgba(8, 48, 80, 0.86) 100%), url("${imageUrl}"); background-position:center; background-size:cover; background-repeat:no-repeat;`;
    }

    get themeStyle() {
        return [
            `--bg:${this.safeColor(this.config?.primaryColor, '#0B5A7A')}`,
            `--bg-dark:${this.safeColor(this.config?.secondaryColor, '#0A4E6B')}`,
            `--bg-header:${this.safeColor(this.config?.secondaryColor, '#0A4E6B')}`,
            `--yellow:${this.safeColor(this.config?.accentColor, '#F6E85C')}`,
            `--white:${this.safeColor(this.config?.textColor, '#FFFFFF')}`
        ].join(';');
    }

    get questions() {
        return (this.config?.questions || []).map((question) => ({
            ...question,
            options: (question.options || []).map((option) => ({
                ...option,
                cssClass: `range-option${this.answers[question.key] === option.key ? ' active' : ''}`,
                ariaPressed: this.answers[question.key] === option.key ? 'true' : 'false'
            }))
        }));
    }

    get benefitItems() {
        const benefits = Array.isArray(this.content.benefits) ? this.content.benefits : DEFAULT_CONTENT.benefits;
        return benefits.slice(0, 5).map((label) => ({ key: label, label }));
    }

    get savingsAmount() {
        let total = 0;
        (this.config?.questions || []).forEach((question) => {
            const selected = (question.options || []).find((option) => option.key === this.answers[question.key]);
            total += Number(selected?.estimatedSavings || 0);
        });
        return total > 0 ? String(total) : '0';
    }

    get showCpf() {
        return this.config?.showCpf === true;
    }

    get consentLink() {
        return this.safeExternalUrl(this.config?.consentLink);
    }

    get hasConsentLink() {
        return Boolean(this.consentLink);
    }

    get submitLabel() {
        return this.isSubmitting ? this.content.submittingLabel : this.content.submitButtonLabel;
    }

    get finalTitle() {
        if (this.isValidated) {
            return 'Código validado!';
        }
        if (this.isBlocked) {
            return 'Cadastro já realizado!';
        }
        return this.content.successTitle;
    }

    get finalMessage() {
        if (this.statusMessage) {
            return this.statusMessage;
        }
        return this.isCheckingDelivery ? 'Estamos enviando seu código...' : this.content.codeSentMessage;
    }

    get showCodeForm() {
        return this.deliveryReady && !this.isBlocked && !this.isValidated;
    }

    get showRetryButton() {
        return this.canRetryDelivery && !this.isCheckingDelivery;
    }

    get validationButtonDisabled() {
        return this.isValidating || !this.giftCode.trim();
    }

    get whatsappDisplayValue() {
        return this.formatPhone(this.formData.mobilePhone);
    }

    goToStep2() {
        this.resetMessages();
        this.currentStep = 2;
    }

    selectAnswer(event) {
        const { question, option } = event.currentTarget.dataset;
        this.answers = { ...this.answers, [question]: option };
    }

    goToStep3() {
        const missingRequired = (this.config?.questions || []).some(
            (question) => question.required && !this.answers[question.key]
        );
        if (missingRequired) {
            this.errorMessage = 'Responda às perguntas da simulação.';
            return;
        }
        this.resetMessages();
        this.currentStep = 3;
    }

    handleFormChange(event) {
        const { name, value, checked, type } = event.target;
        this.formData = { ...this.formData, [name]: type === 'checkbox' ? checked : value };
    }

    handlePhoneInput(event) {
        this.formData = { ...this.formData, mobilePhone: this.digits(event.target.value, 13) };
    }

    handleCpfInput(event) {
        this.formData = { ...this.formData, cpf: this.digits(event.target.value, 11) };
    }

    async handleSubmit() {
        if (this.isSubmitting) {
            return;
        }
        this.resetMessages();
        if (!this.validateForm()) {
            return;
        }

        this.isSubmitting = true;
        this.requestId = this.requestId || this.newRequestId();
        try {
            const response = await requestCode({
                requestData: {
                    requestId: this.requestId,
                    configurationKey: this.configurationKey,
                    fullName: this.formData.fullName.trim(),
                    cpf: this.formData.cpf || null,
                    email: this.formData.email.trim(),
                    mobilePhone: this.formData.mobilePhone,
                    consentAccepted: this.formData.consentAccepted,
                    answersJson: JSON.stringify(this.answers)
                }
            });
            this.accessToken = response.accessToken;
            this.persistSession();
            this.currentStep = 4;
            if (response.status === 'BLOQUEADO') {
                this.isBlocked = true;
                this.statusMessage = response.message;
            } else {
                this.startDeliveryPolling();
            }
        } catch (error) {
            this.errorMessage = this.errorText(error, 'Não foi possível processar a solicitação.');
        } finally {
            this.isSubmitting = false;
        }
    }

    startDeliveryPolling() {
        this.isCheckingDelivery = true;
        this.canRetryDelivery = false;
        this.pollAttempts = 0;
        this.checkDelivery();
    }

    async checkDelivery() {
        this.clearPollTimer();
        if (!this.accessToken) {
            return;
        }
        try {
            const response = await getDeliveryStatus({ accessToken: this.accessToken });
            this.applyDeliveryStatus(response);
            if (response.status === 'PROCESSANDO' && this.pollAttempts < MAX_POLL_ATTEMPTS) {
                this.pollAttempts += 1;
                this.pollTimer = setTimeout(() => this.checkDelivery(), POLL_INTERVAL_MS);
            } else if (response.status === 'PROCESSANDO') {
                this.isCheckingDelivery = false;
                this.statusMessage = 'O envio está demorando mais que o esperado. Você pode tentar novamente.';
                this.canRetryDelivery = true;
            }
        } catch (error) {
            this.isCheckingDelivery = false;
            this.statusMessage = this.errorText(error, 'Não foi possível consultar o envio.');
            this.canRetryDelivery = true;
        }
    }

    applyDeliveryStatus(response) {
        this.isCheckingDelivery = response.status === 'PROCESSANDO';
        this.deliveryReady = response.status === 'ENVIADO';
        this.isBlocked = response.status === 'BLOQUEADO';
        this.isValidated = response.status === 'VALIDADO';
        this.canRetryDelivery = response.canRetry === true;
        this.statusMessage = response.message || '';
        if (this.isValidated) {
            this.clearPersistedSession();
        }
    }

    async handleRetryDelivery() {
        this.canRetryDelivery = false;
        this.isCheckingDelivery = true;
        this.statusMessage = 'Tentando enviar novamente...';
        try {
            const response = await retryDelivery({ accessToken: this.accessToken });
            this.applyDeliveryStatus(response);
            if (response.status === 'PROCESSANDO') {
                this.startDeliveryPolling();
            }
        } catch (error) {
            this.isCheckingDelivery = false;
            this.canRetryDelivery = true;
            this.statusMessage = this.errorText(error, 'Não foi possível reenviar o código.');
        }
    }

    handleGiftCode(event) {
        this.giftCode = (event.target.value || '').toUpperCase().slice(0, 30);
    }

    async handleValidateCode() {
        this.isValidating = true;
        this.errorMessage = '';
        try {
            const response = await validateCode({
                requestData: { accessToken: this.accessToken, code: this.giftCode }
            });
            if (response.valid) {
                this.isValidated = true;
                this.deliveryReady = false;
                this.statusMessage = response.message;
                this.clearPersistedSession();
            } else {
                this.errorMessage = response.message;
            }
        } catch (error) {
            this.errorMessage = this.errorText(error, 'Não foi possível validar o código.');
        } finally {
            this.isValidating = false;
        }
    }

    restart() {
        this.clearPollTimer();
        this.clearPersistedSession();
        this.currentStep = 1;
        this.answers = {};
        this.formData = { fullName: '', cpf: '', mobilePhone: '', email: '', consentAccepted: false };
        this.giftCode = '';
        this.requestId = null;
        this.accessToken = null;
        this.deliveryReady = false;
        this.isBlocked = false;
        this.isValidated = false;
        this.isCheckingDelivery = false;
        this.canRetryDelivery = false;
        this.resetMessages();
    }

    validateForm() {
        const inputs = [...this.template.querySelectorAll('.form-fields input:not([type="checkbox"])')];
        const nativeValid = inputs.reduce((valid, input) => {
            input.reportValidity();
            return input.checkValidity() && valid;
        }, true);
        if (!nativeValid) {
            this.errorMessage = 'Revise os campos destacados.';
            return false;
        }
        if (this.config?.requirePhone && this.formData.mobilePhone.length < 10) {
            this.errorMessage = 'Informe um WhatsApp válido.';
            return false;
        }
        if (this.config?.requireCpf && this.formData.cpf.length !== 11) {
            this.errorMessage = 'Informe um CPF válido.';
            return false;
        }
        if (this.config?.requireConsent && !this.formData.consentAccepted) {
            this.errorMessage = 'Aceite o consentimento para continuar.';
            return false;
        }
        return true;
    }

    async restoreSession() {
        try {
            const saved = window.sessionStorage.getItem(this.sessionKey);
            if (!saved) {
                return;
            }
            const session = JSON.parse(saved);
            if (!session?.accessToken || !session?.requestId) {
                return;
            }
            this.accessToken = session.accessToken;
            this.requestId = session.requestId;
            this.currentStep = 4;
            const response = await getDeliveryStatus({ accessToken: this.accessToken });
            this.applyDeliveryStatus(response);
            if (response.status === 'PROCESSANDO') {
                this.startDeliveryPolling();
            }
        } catch (error) {
            this.currentStep = 4;
            this.statusMessage = this.errorText(
                error,
                'Não foi possível restaurar a solicitação. Tente novamente.'
            );
            this.canRetryDelivery = true;
        }
    }

    persistSession() {
        try {
            window.sessionStorage.setItem(
                this.sessionKey,
                JSON.stringify({ accessToken: this.accessToken, requestId: this.requestId })
            );
        } catch (error) {
            // A jornada continua mesmo quando o storage está bloqueado pelo navegador.
        }
    }

    clearPersistedSession() {
        try {
            window.sessionStorage.removeItem(this.sessionKey);
        } catch (error) {
            // Sem ação: o token expira pelas regras do servidor.
        }
    }

    get sessionKey() {
        return `totem-leads:${(this.configurationKey || 'VEO').toUpperCase()}`;
    }

    newRequestId() {
        if (window.crypto?.randomUUID) {
            return window.crypto.randomUUID();
        }
        return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (character) => {
            const random = Math.floor(Math.random() * 16);
            const value = character === 'x' ? random : (random & 0x3) | 0x8;
            return value.toString(16);
        });
    }

    resolveAsset(value, fallback) {
        if (typeof value !== 'string' || !value.trim()) {
            return fallback;
        }
        const normalized = value.trim();
        const staticPrefix = '/resource/TotemFiles/';
        if (normalized.startsWith(staticPrefix)) {
            return `${TOTEM_FILES}/${normalized.slice(staticPrefix.length)}`;
        }
        return normalized.startsWith('/sfsites/') || normalized.startsWith('./') ? normalized : fallback;
    }

    safeColor(value, fallback) {
        return typeof value === 'string' && HEX_COLOR_REGEX.test(value.trim()) ? value.trim() : fallback;
    }

    safeExternalUrl(value) {
        return typeof value === 'string' && /^https:\/\//i.test(value.trim()) ? value.trim() : null;
    }

    digits(value, maxLength) {
        return (value || '').replace(/\D/g, '').slice(0, maxLength);
    }

    formatPhone(value) {
        const digits = this.digits(value, 11);
        if (digits.length <= 2) return digits ? `(${digits}` : '';
        if (digits.length <= 6) return `(${digits.slice(0, 2)}) ${digits.slice(2)}`;
        if (digits.length <= 10) {
            return `(${digits.slice(0, 2)}) ${digits.slice(2, 6)} - ${digits.slice(6)}`;
        }
        return `(${digits.slice(0, 2)}) ${digits.slice(2, 7)} - ${digits.slice(7)}`;
    }

    resetMessages() {
        this.errorMessage = '';
        this.statusMessage = '';
    }

    clearPollTimer() {
        if (this.pollTimer) {
            clearTimeout(this.pollTimer);
            this.pollTimer = null;
        }
    }

    errorText(error, fallback) {
        return error?.body?.message || error?.message || fallback;
    }
}