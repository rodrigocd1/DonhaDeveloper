import { LightningElement, api, track } from 'lwc';
import TOTEM_FILES from '@salesforce/resourceUrl/TotemFiles';
import localizarCadastroPorValor from '@salesforce/apex/TotemOportunidadesController.localizarCadastroPorValor';
import confirmarDadosClientePorValor from '@salesforce/apex/TotemOportunidadesController.confirmarDadosClientePorValor';
import converterLeadPendente from '@salesforce/apex/TotemOportunidadesController.converterLeadPendente';
import carregarDadosContaEnergia from '@salesforce/apex/TotemOportunidadesController.carregarDadosContaEnergia';
import salvarEscolhasContaEnergia from '@salesforce/apex/TotemOportunidadesController.salvarEscolhasContaEnergia';
import processarContaEnergia from '@salesforce/apex/TotemOportunidadesController.processarContaEnergia';
import processarAdesaoPorValor from '@salesforce/apex/TotemOportunidadesController.processarAdesaoPorValor';

const SEARCH_TYPES = [
    { label: 'Código do cliente', value: 'CODIGO' },
    { label: 'WhatsApp', value: 'WHATSAPP' },
    { label: 'E-mail', value: 'EMAIL' }
];

const LOOKUP_STATE = {
    SEARCH: 'SEARCH',
    NEEDS_CPF: 'NEEDS_CPF',
    NOT_FOUND: 'NOT_FOUND',
    CONFIRM: 'CONFIRM',
    CLOSED: 'CLOSED'
};

const ENERGY_INPUT_MODE = {
    AVERAGE: 'AVERAGE',
    BILL: 'BILL'
};
const CONVERSION_RETRY_DELAY_MS = 850;
const CONVERSION_RETRY_ATTEMPTS = 5;

const ENERGY_RANGES = [
    { label: 'Até R$200', value: 'Menor que R$200', amount: 200 },
    { label: 'R$200 a R$500', value: 'R$200 a R$500', amount: 350 },
    { label: 'R$500 a R$700', value: 'R$500 a R$700', amount: 600 },
    { label: 'Acima de R$700', value: 'R$700 a R$1.000', amount: 850 }
];

const DEFAULT_TEXT = {
    brandName: 'VEO Energia',
    step1SidebarTitle: 'Localize o cadastro.',
    step1PanelTitle: 'Localizacao.',
    step1PanelSubtitle: 'Busque o cliente para continuar a jornada.',
    step2SidebarTitle: 'Sua conta de energia.',
    step3SidebarTitle: 'Veja sua economia.',
    step4SidebarTitle: 'Finalize sua adesão.',
    step5SidebarTitle: 'Cadastro concluído!',
    step5SidebarMessage: 'Em breve a VEO dará continuidade ao processo.',
    simulationBrandText: 'com a VEO Energia',
    primaryButtonLabel: 'Continuar',
    resultButtonLabel: 'Ver Resultado',
    secondaryButtonLabel: 'Refazer análise',
    reviewButtonLabel: 'Confirmar Adesão',
    reviewBackButtonLabel: 'Voltar',
    submittingLabel: 'Processando...',
    successTitle: 'Cadastro concluído!',
    successMessage: 'Sua adesão foi registrada com sucesso.',
    successDetail: 'Em breve a VEO dará continuidade ao processo.',
    successCodeLabel: 'Código do atendimento',
    successRestartLabel: 'Novo atendimento',
    searchButtonLabel: 'Buscar cadastro',
    searchAgainLabel: 'Tentar novamente',
    newCustomerLabel: 'Cadastrar novo cliente',
    confirmDataButtonLabel: 'Confirmar dados',
    invalidCodeMessage: 'Não foi possível validar o código informado. Verifique o código digitado ou reinicie o cadastro.',
    notFoundMessage: 'Não encontramos um cadastro com os dados informados. Verifique as informações ou inicie um novo cadastro.',
    ambiguousMessage: 'Encontramos mais de um cadastro possível. Confirme o CPF do cliente para continuar.',
    closedOpportunityMessage: 'Cliente já possui uma adesão encerrada. A oportunidade não foi alterada automaticamente.',
    termsConsentText: 'Li e aceito os Termos e Condições da VEO Energia.',
    privacyConsentText: 'Li e aceito os Termos de privacidade e LGPD da VEO Energia.',
    contractConsentText: 'Li e aceito o Contrato de adesão da VEO Energia.',
    procuracaoConsentText: 'Li e aceito a Procuração para representação junto à distribuidora, quando aplicável.',
    contactConsentText: 'Autorizo o contato via WhatsApp para acompanhamento.',
    clicksignTitle: 'Assinatura eletrônica',
    clicksignDisabledText: 'Integração Clicksign pendente de configuração. A assinatura eletrônica ainda não será iniciada nesta jornada.',
    clicksignEnabledText: 'Integração Clicksign ativa. A adesão somente poderá ser confirmada após retorno válido da assinatura.',
    clicksignSandboxText: 'Ambiente de testes preparado para inicialização do widget.',
    benefitsStep1: 'Sem obras ou instalacao;Energia 100% renovavel;Economia garantida',
    benefitsStep2: 'Foto ou arquivo da conta;Possui energia solar?;Tipo de ligacao eletrica',
    benefitsStep3: 'Calculo baseado no seu perfil;Sem fidelidade minima;Ativacao em ate 30 dias',
    benefitsStep4: 'Revisao dos seus dados;Aceite dos termos;Ativacao iniciada'
};

const DEFAULT_THEME = {
    primaryColor: '#074f70',
    secondaryColor: '#053d57',
    accentColor: '#f6eb60',
    textColor: '#ffffff',
    surfaceColor: '#e8edef'
};

const DEFAULT_IMAGES = {
    primaryLogoUrl: `${TOTEM_FILES}/logo_white.png`,
    backgroundImageUrl: `${TOTEM_FILES}/background_totem_Oportunidades_JPG.JPG`
};

const HEX_COLOR_REGEX = /^#([0-9a-fA-F]{6})$/;
const SAFE_URL_PREFIXES = ['/resource/', '/sfsites/', './'];
const ACCEPTED_BILL_EXTENSIONS = ['pdf', 'jpg', 'jpeg', 'png'];

function normalizeText(value, fallback, maxLength = 240) {
    if (typeof value !== 'string') {
        return fallback;
    }

    const normalized = value.trim().replace(/\s+/g, ' ');
    if (!normalized) {
        return fallback;
    }

    return normalized.slice(0, maxLength);
}

function normalizeColor(value, fallback) {
    if (typeof value !== 'string') {
        return fallback;
    }

    const normalized = value.trim();
    return HEX_COLOR_REGEX.test(normalized) ? normalized : fallback;
}

function normalizeImageUrl(value, fallback) {
    if (typeof value !== 'string') {
        return fallback;
    }

    const normalized = value.trim();
    if (!normalized) {
        return fallback;
    }

    return SAFE_URL_PREFIXES.some((prefix) => normalized.startsWith(prefix)) ? normalized : fallback;
}

function normalizeDelimitedTextList(value, fallback) {
    const source = typeof value === 'string' && value.trim() ? value : fallback;

    return source
        .split(';')
        .map((item) => item.trim())
        .filter(Boolean)
        .slice(0, 5)
        .map((label, index) => ({ key: `${index}-${label}`, label }));
}

function normalizeBoolean(value) {
    return value === true || value === 'true' || value === '1';
}

function wait(ms) {
    return new Promise((resolve) => {
        window.setTimeout(resolve, ms);
    });
}

export default class TotemOportunidadesFluxo extends LightningElement {
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
    @api primaryButtonLabel;
    @api secondaryButtonLabel;
    @api successTitle;
    @api successMessage;
    @api successDetail;
    @api termsConsentText;
    @api privacyConsentText;
    @api contractConsentText;
    @api procuracaoConsentText;
    @api contactConsentText;
    @api showProcuracaoConsent;
    @api clicksignEnabled;
    @api clicksignUrl;
    @api clicksignEnvironment = 'sandbox';
    @api clicksignTemplate;
    @api clicksignParams;
    @api leadSource = 'Totem Oportunidades';
    @api leadOrigin = 'totem-oportunidades-veo';
    @api formWeb = 'totem_oportunidades';
    @api partnerCode;
    @api campaignCode;
    @api pageIdentifier;
    @api showDevControls;
    @api codeValidityDays = 30;
    @api maxBillFileSizeMb = 4;
    @api invalidCodeMessage;
    @api notFoundMessage;
    @api ambiguousMessage;
    @api closedOpportunityMessage;
    @api benefitsStep1;
    @api benefitsStep2;
    @api benefitsStep3;
    @api benefitsStep4;

    @track currentStep = 1;
    @track lookupState = LOOKUP_STATE.SEARCH;
    @track lookupMessage = '';
    @track lookupMatches = [];
    @track searchData = {
        type: 'CODIGO',
        value: '',
        cpf: ''
    };
    @track formData = {
        nomeCompleto: '',
        cpf: '',
        dataNasc: '',
        whatsapp: '',
        email: '',
        aceitaTermos: false,
        aceitaPrivacidade: false,
        aceitaContrato: false,
        aceitaProcuracao: false,
        aceitaContato: false
    };
    @track hasSolar = null;
    @track selectedLigacao = null;
    @track selectedEnergyInputMode = ENERGY_INPUT_MODE.AVERAGE;
    @track selectedRange = null;
    @track manualMonthlyCost = null;
    @track manualEnergySaved = false;
    @track energyData = null;
    @track billCaptureMode = null;
    @track billFileName = '';
    @track billFileBase64 = '';
    @track billFileType = '';
    @track billPreviewUrl = '';
    @track isCameraOpen = false;
    @track isProcessingBill = false;
    @track billRecognitionValid = false;
    @track billStatusMessage = '';
    @track errorMessage = '';
    @track isSearching = false;
    @track isConfirmingCustomer = false;
    @track isSubmitting = false;
    @track opportunityCode = '';
    @track clicksignStatus = 'DISABLED';
    @track clicksignDocumentId = '';
    @track clicksignSignatureKey = '';
    @track isClicksignLoading = false;
    @track localizedLeadId = null;
    @track localizedOpportunityId = null;
    @track validatedByCode = false;
    @track allowCreateNew = false;
    cameraStream = null;

    disconnectedCallback() {
        this.stopCamera();
    }

    get resolvedBrandName() {
        return normalizeText(this.brandName, DEFAULT_TEXT.brandName, 80);
    }

    get resolvedPrimaryColor() {
        return normalizeColor(this.primaryColor, DEFAULT_THEME.primaryColor);
    }

    get resolvedSecondaryColor() {
        return normalizeColor(this.secondaryColor, DEFAULT_THEME.secondaryColor);
    }

    get resolvedAccentColor() {
        return normalizeColor(this.accentColor, DEFAULT_THEME.accentColor);
    }

    get resolvedTextColor() {
        return normalizeColor(this.textColor, DEFAULT_THEME.textColor);
    }

    get resolvedSurfaceColor() {
        return normalizeColor(this.surfaceColor, DEFAULT_THEME.surfaceColor);
    }

    get themeStyle() {
        return [
            `--veo-blue:${this.resolvedPrimaryColor}`,
            `--veo-blue-dark:${this.resolvedSecondaryColor}`,
            `--veo-blue-ink:${this.resolvedPrimaryColor}`,
            `--veo-blue-soft:${this.resolvedAccentColor}`,
            `--veo-yellow:${this.resolvedAccentColor}`,
            `--veo-white:${this.resolvedTextColor}`,
            `--veo-gray:${this.resolvedSurfaceColor}`
        ].join(';');
    }

    /* ── Step flags ─────────────────────────────────────────── */
    get isStep1() { return this.currentStep === 1; }
    get isStep2() { return this.currentStep === 2; }
    get isStep3() { return this.currentStep === 3; }
    get isStep4() { return this.currentStep === 4; }
    get isStep5() { return this.currentStep === 5; }
    get stepLabel() { return String(this.currentStep).padStart(2, '0'); }

    get isLookupSearch() {
        return this.lookupState === LOOKUP_STATE.SEARCH;
    }

    get isLookupNeedsCpf() {
        return this.lookupState === LOOKUP_STATE.NEEDS_CPF;
    }

    get isLookupNotFound() {
        return this.lookupState === LOOKUP_STATE.NOT_FOUND;
    }

    get isLookupConfirm() {
        return this.lookupState === LOOKUP_STATE.CONFIRM;
    }

    get isLookupClosed() {
        return this.lookupState === LOOKUP_STATE.CLOSED;
    }

    get hasLookupMessage() {
        return Boolean(this.lookupMessage);
    }

    get searchOptions() {
        return SEARCH_TYPES.map((option) => ({
            ...option,
            cssClass: `search-type-btn${this.searchData.type === option.value ? ' active' : ''}`
        }));
    }

    get searchInputLabel() {
        if (this.searchData.type === 'WHATSAPP') {
            return 'WhatsApp';
        }
        if (this.searchData.type === 'EMAIL') {
            return 'E-mail';
        }
        return 'Código do cliente';
    }

    get searchInputType() {
        return this.searchData.type === 'EMAIL' ? 'email' : 'text';
    }

    get searchInputMode() {
        return this.searchData.type === 'WHATSAPP' ? 'numeric' : 'text';
    }

    get searchInputPlaceholder() {
        if (this.searchData.type === 'WHATSAPP') {
            return '(00) 00000-0000';
        }
        if (this.searchData.type === 'EMAIL') {
            return 'cliente@email.com';
        }
        return 'VEO-00000';
    }

    get resolvedSearchButtonLabel() {
        return this.isSearching ? this.resolvedSubmittingLabel : DEFAULT_TEXT.searchButtonLabel;
    }

    get resolvedInvalidCodeMessage() {
        return normalizeText(this.invalidCodeMessage, DEFAULT_TEXT.invalidCodeMessage, 240);
    }

    get resolvedNotFoundMessage() {
        return normalizeText(this.notFoundMessage, DEFAULT_TEXT.notFoundMessage, 240);
    }

    get resolvedAmbiguousMessage() {
        return normalizeText(this.ambiguousMessage, DEFAULT_TEXT.ambiguousMessage, 240);
    }

    get resolvedClosedOpportunityMessage() {
        return normalizeText(this.closedOpportunityMessage, DEFAULT_TEXT.closedOpportunityMessage, 240);
    }

    get resolvedSearchAgainLabel() {
        return DEFAULT_TEXT.searchAgainLabel;
    }

    get resolvedNewCustomerLabel() {
        return DEFAULT_TEXT.newCustomerLabel;
    }

    get resolvedConfirmDataLabel() {
        return DEFAULT_TEXT.confirmDataButtonLabel;
    }

    get resolvedConfirmCustomerButtonLabel() {
        return this.isConfirmingCustomer ? this.resolvedSubmittingLabel : this.resolvedConfirmDataLabel;
    }

    get stepDots() {
        return [1, 2, 3, 4, 5].map((n) => ({
            key: n,
            cls: n === 1 ? 'dot dot-active' : 'dot'
        }));
    }

    /* ── Button state getters ───────────────────────────────── */
    get solarSimClass() {
        return `toggle-btn${this.hasSolar === true ? ' active' : ''}`;
    }

    get solarNaoClass() {
        return `toggle-btn${this.hasSolar === false ? ' active' : ''}`;
    }

    get isSolarYes() {
        return this.hasSolar === true;
    }

    get isSolarNo() {
        return this.hasSolar === false;
    }

    get ligacaoMonoClass() { return `lig-btn${this.selectedLigacao === 'mono' ? ' active' : ''}`; }
    get ligacaoBiClass()   { return `lig-btn${this.selectedLigacao === 'bi'   ? ' active' : ''}`; }
    get ligacaoTriClass()  { return `lig-btn${this.selectedLigacao === 'tri'  ? ' active' : ''}`; }

    get isAverageMode() {
        return this.selectedEnergyInputMode === ENERGY_INPUT_MODE.AVERAGE;
    }

    get isBillMode() {
        return this.selectedEnergyInputMode === ENERGY_INPUT_MODE.BILL;
    }

    get averageModeClass() {
        return `energy-mode-btn${this.isAverageMode ? ' active' : ''}`;
    }

    get billModeClass() {
        return `energy-mode-btn${this.isBillMode ? ' active' : ''}`;
    }

    get energyRanges() {
        return ENERGY_RANGES.map((range) => ({
            ...range,
            cssClass: `range-btn${this.selectedRange === range.value ? ' active' : ''}`
        }));
    }

    get hasUsableEnergyInput() {
        return Boolean(
            this.billRecognitionValid ||
            this.energyData?.hasRequiredEnergyData ||
            this.energyData?.hasRecognizedBillData ||
            this.energyData?.hasManualEstimate ||
            (this.manualEnergySaved && this.numberOrNull(this.energyData?.contaEstimada) > 0)
        );
    }

    get acceptedBillFormats() {
        return '.pdf,.jpg,.jpeg,.png,application/pdf,image/jpeg,image/png';
    }

    get hasBillFile() {
        return Boolean(this.billFileBase64);
    }

    get hasBillPreview() {
        return Boolean(this.billPreviewUrl);
    }

    get isBillPdf() {
        return this.billFileType === 'application/pdf' || this.fileExtension(this.billFileName) === 'pdf';
    }

    get isCameraCapture() {
        return this.billCaptureMode === 'CAMERA';
    }

    get billActionLabel() {
        if (this.isProcessingBill) {
            return 'Analisando...';
        }
        if (this.isAverageMode) {
            return this.resolvedResultLabel;
        }
        return this.billRecognitionValid ? this.resolvedResultLabel : 'Analisar conta';
    }

    get billActionDisabled() {
        return this.isProcessingBill;
    }

    /* ── Simulation values ──────────────────────────────────── */
    get sim() {
        const data = this.energyData || {};
        return {
            conta: this.firstNumber(data.contaEstimada, data.monthlyCost),
            desconto: this.numberOrNull(data.descontoPercent),
            mensal: this.numberOrNull(data.economiaMensal),
            anual: this.numberOrNull(data.economiaAnual)
        };
    }

    get hasSimulationData() {
        return this.energyData?.hasSimulationData === true;
    }

    get currentBillLabel() {
        return this.energyData?.hasManualEstimate ? 'Valor médio da conta' : 'Valor atual estimado';
    }

    get contaEstimadaDisplay() {
        return this.formatCurrency(this.sim.conta, '/mês');
    }

    get savingsMonthlyDisplay() {
        return this.formatCurrency(this.sim.mensal, '/mês');
    }

    get economiaAnualDisplay() {
        return this.formatCurrency(this.sim.anual, '/ano');
    }

    get descontoPercentDisplay() {
        return this.formatPercent(this.sim.desconto);
    }

    get simulationMessage() {
        return this.energyData?.simulationMessage || 'Simulação ainda não disponível para os dados informados.';
    }

    get simulationRuleText() {
        return 'Cálculo com desconto VEO fixo de 15%.';
    }

    get renewableInfoText() {
        return this.energyData?.renewableInfo || 'Energia renovável com créditos compensados pela VEO.';
    }

    get savingsActionDisabled() {
        return !this.hasSimulationData;
    }

    get savingsActionLabel() {
        return 'Quero economizar';
    }

    get simulationSecondaryActionLabel() {
        return this.isBillMode ? 'Reenviar conta' : 'Refazer análise';
    }

    get contactPhoneDisplay() {
        return this.formData.whatsapp.trim() || 'Não informado';
    }

    get contactEmailDisplay() {
        return this.formData.email.trim() || 'Não informado';
    }

    get isClicksignEnabled() {
        return normalizeBoolean(this.clicksignEnabled);
    }

    get isClicksignDisabled() {
        return !this.isClicksignEnabled;
    }

    get effectiveClicksignStatus() {
        if (!this.isClicksignEnabled) {
            return 'DISABLED';
        }
        if (this.isClicksignLoading) {
            return 'LOADING';
        }
        return this.clicksignStatus && this.clicksignStatus !== 'DISABLED' ? this.clicksignStatus : 'PENDING';
    }

    get clicksignStatusLabel() {
        const labels = {
            DISABLED: 'Integração desativada',
            PENDING: 'Assinatura pendente',
            LOADING: 'Carregando assinatura',
            SIGNED: 'Assinatura concluída',
            CANCELED: 'Assinatura cancelada',
            ERROR: 'Erro na assinatura'
        };
        return labels[this.effectiveClicksignStatus] || labels.PENDING;
    }

    get clicksignStatusClass() {
        return `clicksign-status clicksign-status-${this.effectiveClicksignStatus.toLowerCase()}`;
    }

    get clicksignConfigDisplay() {
        const items = [];
        if (this.clicksignEnvironment) {
            items.push(`Ambiente: ${this.clicksignEnvironment}`);
        }
        if (this.clicksignTemplate) {
            items.push(`Modelo: ${this.clicksignTemplate}`);
        }
        if (this.clicksignUrl) {
            items.push('URL configurada');
        }
        if (this.clicksignParams) {
            items.push('Parâmetros configurados');
        }
        return items.length ? items.join(' | ') : 'Configuração externa pendente';
    }

    get clicksignRequirementSatisfied() {
        return !this.isClicksignEnabled || this.effectiveClicksignStatus === 'SIGNED';
    }

    get shouldShowProcuracaoConsent() {
        return normalizeBoolean(this.showProcuracaoConsent);
    }

    get shouldShowContactConsent() {
        return true;
    }

    get hasRequiredCustomerData() {
        return Boolean(
            this.formData.nomeCompleto.trim() &&
            this.formData.cpf.trim() &&
            this.formData.dataNasc.trim()
        );
    }

    get hasRequiredContactData() {
        return Boolean(this.formData.whatsapp.trim() && this.formData.email.trim());
    }

    get resolvedLeadId() {
        return this.localizedLeadId || this.energyData?.leadId || null;
    }

    get resolvedOpportunityId() {
        return this.localizedOpportunityId || this.energyData?.opportunityId || null;
    }

    get hasValidOpportunity() {
        return Boolean(this.resolvedOpportunityId);
    }

    get hasValidEnergyForReview() {
        return Boolean(
            this.hasSimulationData &&
            this.hasUsableEnergyInput &&
            this.numberOrNull(this.sim.conta) > 0
        );
    }

    get hasRequiredReviewConsents() {
        const hasBaseConsents =
            this.formData.aceitaTermos &&
            this.formData.aceitaPrivacidade &&
            this.formData.aceitaContrato;
        const hasProcuracaoConsent = !this.shouldShowProcuracaoConsent || this.formData.aceitaProcuracao;
        const hasContactConsent = !this.shouldShowContactConsent || this.formData.aceitaContato;
        return Boolean(hasBaseConsents && hasProcuracaoConsent && hasContactConsent);
    }

    get isReviewReady() {
        return Boolean(
            this.hasRequiredCustomerData &&
            this.hasRequiredContactData &&
            this.hasValidEnergyForReview &&
            this.hasValidOpportunity &&
            this.hasRequiredReviewConsents &&
            this.clicksignRequirementSatisfied
        );
    }

    get confirmAdhesionDisabled() {
        return this.isSubmitting || !this.isReviewReady;
    }

    get logoUrl() {
        return normalizeImageUrl(this.primaryLogoUrl, DEFAULT_IMAGES.primaryLogoUrl);
    }

    get sidebarPhotoStyle() {
        const backgroundUrl = normalizeImageUrl(
            this.backgroundImageUrl,
            DEFAULT_IMAGES.backgroundImageUrl
        );

        return `background-image: linear-gradient(180deg, rgba(7, 79, 112, 0.02) 0%, rgba(7, 79, 112, 0.16) 43%, rgba(7, 79, 112, 0.72) 76%, rgba(7, 79, 112, 0.95) 100%), url("${backgroundUrl}"); background-position: center center; background-size: cover; background-repeat: no-repeat;`;
    }

    get resolvedStep1SidebarTitle() {
        return normalizeText(this.heroTitle, DEFAULT_TEXT.step1SidebarTitle, 120);
    }

    get resolvedStep1PanelTitle() {
        return DEFAULT_TEXT.step1PanelTitle;
    }

    get resolvedStep1PanelSubtitle() {
        return normalizeText(this.heroSubtitle, DEFAULT_TEXT.step1PanelSubtitle, 200);
    }

    get resolvedStep2SidebarTitle() {
        return DEFAULT_TEXT.step2SidebarTitle;
    }

    get resolvedStep3SidebarTitle() {
        return DEFAULT_TEXT.step3SidebarTitle;
    }

    get resolvedStep4SidebarTitle() {
        return DEFAULT_TEXT.step4SidebarTitle;
    }

    get resolvedStep5SidebarTitle() {
        return DEFAULT_TEXT.step5SidebarTitle;
    }

    get resolvedStep5SidebarMessage() {
        return normalizeText(this.successDetail, DEFAULT_TEXT.step5SidebarMessage, 240);
    }

    get resolvedSimulationBrandText() {
        return `com a ${this.resolvedBrandName}`;
    }

    get resolvedContinueLabel() {
        return normalizeText(this.primaryButtonLabel, DEFAULT_TEXT.primaryButtonLabel, 60);
    }

    get resolvedResultLabel() {
        return DEFAULT_TEXT.resultButtonLabel;
    }

    get resolvedSecondaryLabel() {
        return normalizeText(this.secondaryButtonLabel, DEFAULT_TEXT.secondaryButtonLabel, 60);
    }

    get resolvedReviewLabel() {
        return DEFAULT_TEXT.reviewButtonLabel;
    }

    get resolvedReviewBackLabel() {
        return DEFAULT_TEXT.reviewBackButtonLabel;
    }

    get resolvedSubmittingLabel() {
        return DEFAULT_TEXT.submittingLabel;
    }

    get resolvedSuccessTitle() {
        return normalizeText(this.successTitle, DEFAULT_TEXT.successTitle, 100);
    }

    get resolvedSuccessMessage() {
        return normalizeText(this.successMessage, DEFAULT_TEXT.successMessage, 200);
    }

    get resolvedSuccessDetail() {
        return normalizeText(this.successDetail, DEFAULT_TEXT.successDetail, 240);
    }

    get hasOpportunityCode() {
        return Boolean(this.opportunityCode);
    }

    get opportunityCodeDisplay() {
        return this.opportunityCode || '';
    }

    get resolvedSuccessCodeLabel() {
        return DEFAULT_TEXT.successCodeLabel;
    }

    get resolvedTermsConsentText() {
        return normalizeText(this.termsConsentText, DEFAULT_TEXT.termsConsentText, 240);
    }

    get resolvedPrivacyConsentText() {
        return normalizeText(this.privacyConsentText, DEFAULT_TEXT.privacyConsentText, 240);
    }

    get resolvedContractConsentText() {
        return normalizeText(this.contractConsentText, DEFAULT_TEXT.contractConsentText, 240);
    }

    get resolvedProcuracaoConsentText() {
        return normalizeText(this.procuracaoConsentText, DEFAULT_TEXT.procuracaoConsentText, 240);
    }

    get resolvedContactConsentText() {
        return normalizeText(this.contactConsentText, DEFAULT_TEXT.contactConsentText, 240);
    }

    get resolvedClicksignTitle() {
        return DEFAULT_TEXT.clicksignTitle;
    }

    get resolvedClicksignDisabledText() {
        return DEFAULT_TEXT.clicksignDisabledText;
    }

    get resolvedClicksignEnabledText() {
        return DEFAULT_TEXT.clicksignEnabledText;
    }

    get resolvedClicksignSandboxText() {
        return DEFAULT_TEXT.clicksignSandboxText;
    }

    get resolvedSuccessRestartLabel() {
        return DEFAULT_TEXT.successRestartLabel;
    }

    get sidebarBenefitsStep1() {
        return normalizeDelimitedTextList(this.benefitsStep1, DEFAULT_TEXT.benefitsStep1);
    }

    get sidebarBenefitsStep2() {
        return normalizeDelimitedTextList(this.benefitsStep2, DEFAULT_TEXT.benefitsStep2);
    }

    get sidebarBenefitsStep3() {
        return normalizeDelimitedTextList(this.benefitsStep3, DEFAULT_TEXT.benefitsStep3);
    }

    get sidebarBenefitsStep4() {
        return normalizeDelimitedTextList(this.benefitsStep4, DEFAULT_TEXT.benefitsStep4);
    }

    get shouldShowDevControls() {
        return this.showDevControls !== false && !this.isStep5;
    }

    /* ── Customer lookup ───────────────────────────────────────── */
    selectSearchType(event) {
        this.searchData = {
            type: event.currentTarget.dataset.value,
            value: '',
            cpf: ''
        };
        this.resetLookupResult();
    }

    handleSearchChange(event) {
        this.searchData = { ...this.searchData, value: event.target.value };
    }

    handleSearchCpfChange(event) {
        this.searchData = { ...this.searchData, cpf: event.target.value };
    }

    getLiveSearchData() {
        const searchInput = this.template.querySelector('input[name="searchValue"]');
        const cpfInput = this.template.querySelector('input[name="searchCpf"]');

        return {
            ...this.searchData,
            value: searchInput ? searchInput.value : this.searchData.value,
            cpf: cpfInput ? cpfInput.value : this.searchData.cpf
        };
    }

    async handleLookupSubmit() {
        const liveSearchData = this.getLiveSearchData();
        this.searchData = liveSearchData;

        if (!liveSearchData.value.trim()) {
            this.errorMessage = `Informe ${this.searchInputLabel}.`;
            return;
        }

        this.errorMessage = '';
        this.lookupMessage = '';
        this.isSearching = true;

        try {
            const result = await localizarCadastroPorValor({
                searchType: liveSearchData.type,
                searchValue: liveSearchData.value,
                cpf: liveSearchData.cpf,
                codeValidityDays: Number(this.codeValidityDays) || 30
            });

            this.handleLookupResult(result || {});
        } catch (error) {
            this.errorMessage =
                error?.body?.message || error?.message || 'Não foi possível localizar o cadastro.';
        } finally {
            this.isSearching = false;
        }
    }

    handleLookupResult(result) {
        this.localizedLeadId = result.leadId || null;
        this.localizedOpportunityId = result.opportunityId || null;
        this.validatedByCode = Boolean(result.validatedByCode);
        this.allowCreateNew = false;
        this.lookupMatches = result.matches || [];

        if (result.status === 'OPEN_OPPORTUNITY' || result.status === 'LEAD_FOUND') {
            this.applyLocatedCustomer(result);
            this.lookupState = LOOKUP_STATE.CONFIRM;
            this.lookupMessage = result.mensagem || 'Cadastro localizado.';
            return;
        }

        if (result.status === 'NEEDS_CPF') {
            this.lookupState = LOOKUP_STATE.NEEDS_CPF;
            this.lookupMessage = this.resolvedAmbiguousMessage;
            return;
        }

        if (result.status === 'NOT_FOUND') {
            this.lookupState = LOOKUP_STATE.NOT_FOUND;
            this.lookupMessage = this.resolvedNotFoundMessage;
            return;
        }

        if (result.status === 'CLOSED_OPPORTUNITY') {
            this.applyLocatedCustomer(result);
            this.lookupState = LOOKUP_STATE.CLOSED;
            this.lookupMessage = this.resolvedClosedOpportunityMessage;
            return;
        }

        if (result.status === 'INVALID_CODE') {
            this.lookupState = LOOKUP_STATE.SEARCH;
            this.errorMessage = this.resolvedInvalidCodeMessage;
            return;
        }

        this.lookupState = LOOKUP_STATE.SEARCH;
        this.errorMessage = result.mensagem || 'Não foi possível localizar o cadastro.';
    }

    applyLocatedCustomer(result) {
        this.formData = {
            ...this.formData,
            nomeCompleto: result.nomeCompleto || '',
            cpf: result.cpf || '',
            dataNasc: result.dataNasc || '',
            whatsapp: result.whatsapp || '',
            email: result.email || ''
        };
    }

    handleLookupTryAgain() {
        this.resetLookupResult();
        this.lookupState = LOOKUP_STATE.SEARCH;
    }

    handleStartNewCustomer() {
        this.localizedLeadId = null;
        this.localizedOpportunityId = null;
        this.validatedByCode = false;
        this.allowCreateNew = true;
        this.lookupMatches = [];
        this.errorMessage = '';
        this.lookupMessage = '';
        this.lookupState = LOOKUP_STATE.CONFIRM;

        this.formData = {
            ...this.formData,
            cpf: this.searchData.cpf || '',
            whatsapp: this.searchData.type === 'WHATSAPP' ? this.searchData.value : '',
            email: this.searchData.type === 'EMAIL' ? this.searchData.value : ''
        };
    }

    resetLookupResult() {
        this.lookupMessage = '';
        this.lookupMatches = [];
        this.errorMessage = '';
        this.localizedLeadId = null;
        this.localizedOpportunityId = null;
        this.validatedByCode = false;
        this.allowCreateNew = false;
    }

    /* ── Form changes ───────────────────────────────────────── */
    handleChange(event) {
        const { name, value } = event.target;
        this.formData = { ...this.formData, [name]: value };
    }

    handleCheck(event) {
        const { name, checked } = event.target;
        this.formData = { ...this.formData, [name]: checked };
    }

    getLiveFormData() {
        const fieldNames = ['nomeCompleto', 'cpf', 'dataNasc', 'whatsapp', 'email'];
        const liveTextData = fieldNames.reduce((data, name) => {
            const input = this.template.querySelector(`[name="${name}"]`);
            return {
                ...data,
                [name]: input ? input.value : this.formData[name]
            };
        }, { ...this.formData });

        const checkboxNames = [
            'aceitaTermos',
            'aceitaPrivacidade',
            'aceitaContrato',
            'aceitaProcuracao',
            'aceitaContato'
        ];

        return checkboxNames.reduce((data, name) => {
            const input = this.template.querySelector(`input[type="checkbox"][name="${name}"]`);
            return {
                ...data,
                [name]: input ? input.checked : this.formData[name]
            };
        }, liveTextData);
    }

    buildCustomerRequest(formData = this.formData) {
        return {
            leadId: this.localizedLeadId,
            opportunityId: this.localizedOpportunityId,
            allowCreateNew: this.allowCreateNew,
            searchType: this.searchData.type,
            searchValue: this.searchData.value,
            nomeCompleto: formData.nomeCompleto,
            cpf: formData.cpf,
            dataNasc: formData.dataNasc,
            email: formData.email,
            whatsapp: formData.whatsapp,
            leadSource: this.leadSource,
            leadOrigin: this.leadOrigin,
            formWeb: this.formWeb,
            partnerCode: this.partnerCode,
            campaignCode: this.campaignCode,
            pageIdentifier: this.pageIdentifier
        };
    }

    getMissingFields(labelsAndValues) {
        return labelsAndValues
            .filter(({ value }) => !value)
            .map(({ label }) => label);
    }

    formatFieldList(fields) {
        if (!fields.length) {
            return '';
        }

        if (fields.length === 1) {
            return fields[0];
        }

        if (fields.length === 2) {
            return `${fields[0]} e ${fields[1]}`;
        }

        return `${fields.slice(0, -1).join(', ')} e ${fields[fields.length - 1]}`;
    }

    async retryPendingLeadConversion(initialResult) {
        let result = initialResult || {};
        let attempts = 0;

        while (result.conversaoPendente && !result.opportunityId && result.leadId && attempts < CONVERSION_RETRY_ATTEMPTS) {
            attempts += 1;
            await wait(CONVERSION_RETRY_DELAY_MS);
            result = await converterLeadPendente({ leadId: result.leadId });
        }

        return result;
    }

    buildPendingConversionLookupRequests(formData = this.formData) {
        const requests = [];
        const email = (formData.email || '').trim();
        const whatsapp = (formData.whatsapp || '').trim();

        if (email) {
            requests.push({ searchType: 'EMAIL', searchValue: email });
        }
        if (whatsapp) {
            requests.push({ searchType: 'WHATSAPP', searchValue: whatsapp });
        }

        return requests;
    }

    async resolveLookupForPendingConversion(lookupResult) {
        if (!lookupResult) {
            return null;
        }

        if (lookupResult.status === 'OPEN_OPPORTUNITY' && lookupResult.opportunityId) {
            return {
                sucesso: true,
                leadId: lookupResult.leadId || null,
                opportunityId: lookupResult.opportunityId,
                mensagem: lookupResult.mensagem || 'Oportunidade localizada.'
            };
        }

        if (lookupResult.status === 'LEAD_FOUND' && lookupResult.leadId) {
            const conversionResult = await converterLeadPendente({ leadId: lookupResult.leadId });
            return this.retryPendingLeadConversion(conversionResult);
        }

        return null;
    }

    async findCadastroForPendingConversion(formData = this.formData) {
        const lookupRequests = this.buildPendingConversionLookupRequests(formData);

        for (const request of lookupRequests) {
            const lookupResult = await localizarCadastroPorValor({
                searchType: request.searchType,
                searchValue: request.searchValue,
                cpf: formData.cpf,
                codeValidityDays: Number(this.codeValidityDays) || 30
            });
            const resolvedResult = await this.resolveLookupForPendingConversion(lookupResult);
            if (resolvedResult?.opportunityId) {
                return resolvedResult;
            }
        }

        return null;
    }

    async resolvePendingLeadConversion(initialResult, formData = this.formData) {
        let result = await this.retryPendingLeadConversion(initialResult);

        if (!result.opportunityId && result.conversaoPendente) {
            const locatedResult = await this.findCadastroForPendingConversion(formData);
            if (locatedResult?.opportunityId) {
                return locatedResult;
            }
        }

        if (!result.opportunityId) {
            const fallbackMessage = result.conversaoPendente
                ? 'Não foi possível localizar a oportunidade gerada para este cadastro. Verifique o e-mail ou celular e tente novamente.'
                : 'Não foi possível converter o Lead e gerar a oportunidade.';
            throw new Error(result.conversaoPendente ? fallbackMessage : (result.mensagem || fallbackMessage));
        }

        return result;
    }

    /* ── Step 1 navigation ──────────────────────────────────── */
    async handleConfirmCustomerData() {
        if (!this.isLookupConfirm) {
            this.errorMessage = 'Localize ou cadastre o cliente antes de continuar.';
            return;
        }

        const liveFormData = this.getLiveFormData();
        this.formData = liveFormData;

        const missingFields = this.getMissingFields([
            { label: 'nome completo', value: liveFormData.nomeCompleto.trim() },
            { label: 'CPF', value: liveFormData.cpf.trim() },
            { label: 'data de nascimento', value: liveFormData.dataNasc.trim() },
            { label: 'WhatsApp', value: liveFormData.whatsapp.trim() },
            { label: 'e-mail', value: liveFormData.email.trim() }
        ]);

        if (missingFields.length) {
            this.errorMessage = `Para continuar, preencha ${this.formatFieldList(missingFields)}.`;
            return;
        }
        this.errorMessage = '';
        this.isConfirmingCustomer = true;

        try {
            const initialResult = await confirmarDadosClientePorValor({
                ...this.buildCustomerRequest(liveFormData)
            });

            if (initialResult?.leadCriado && !initialResult.opportunityId) {
                this.localizedLeadId = initialResult.leadId || this.localizedLeadId;
                this.localizedOpportunityId = null;
                this.opportunityCode = initialResult.codigoUnico || this.opportunityCode;
                this.lookupMessage =
                    initialResult.mensagem ||
                    'Dados confirmados. Clique em Confirmar dados novamente para seguir com a simulação.';
                this.allowCreateNew = false;
                return;
            }

            const result = await this.resolvePendingLeadConversion(initialResult, liveFormData);

            this.localizedLeadId = result.leadId || this.localizedLeadId;
            this.localizedOpportunityId = result.opportunityId || this.localizedOpportunityId;
            this.opportunityCode = result.codigoUnico || this.opportunityCode;
            this.lookupMessage = result.mensagem || this.lookupMessage;
            await this.loadEnergyData();
            this.currentStep = 2;
        } catch (error) {
            this.errorMessage =
                error?.body?.message || error?.message || 'Não foi possível confirmar os dados do cliente.';
        } finally {
            this.isConfirmingCustomer = false;
        }
    }

    advanceToStep2() {
        this.handleConfirmCustomerData();
    }

    async loadEnergyData() {
        const opportunityId = this.resolvedOpportunityId;
        const leadId = this.resolvedLeadId;
        if (!opportunityId && !leadId) {
            return;
        }
        try {
            const result = await carregarDadosContaEnergia({
                opportunityId,
                leadId
            });
            this.applyEnergyData(result || {});
        } catch (error) {
            this.billStatusMessage = '';
        }
    }

    applyEnergyData(data) {
        const selectedManualCost = this.isAverageMode ? this.manualMonthlyCost : null;
        const selectedManualRange = this.isAverageMode ? this.selectedRange : null;
        this.energyData = data || {};
        if (data.opportunityId) {
            this.localizedOpportunityId = data.opportunityId;
        }
        if (data.leadId) {
            this.localizedLeadId = data.leadId;
        }
        if (data.hasSolar !== null && data.hasSolar !== undefined) {
            this.hasSolar = data.hasSolar;
        }
        if (data.tipoLigacao) {
            this.selectedLigacao = data.tipoLigacao;
        }
        if (data.faixaCusto) {
            this.selectedRange = data.faixaCusto;
        }
        const resolvedRange = data.faixaCusto || selectedManualRange || this.selectedRange;
        const rangeMonthlyCost = this.monthlyCostFromRange(resolvedRange);
        const resolvedManualCost = rangeMonthlyCost || selectedManualCost;
        if (this.isAverageMode && resolvedManualCost) {
            this.manualMonthlyCost = resolvedManualCost;
            this.selectedRange = resolvedRange;
            this.energyData = {
                ...this.energyData,
                monthlyCost: resolvedManualCost,
                contaEstimada: resolvedManualCost,
                faixaCusto: resolvedRange
            };
        } else if (data.monthlyCost) {
            this.manualMonthlyCost = Number(data.monthlyCost);
        }
        this.manualEnergySaved = data.hasManualEstimate === true || this.manualEnergySaved;
        this.billRecognitionValid = data.hasRequiredEnergyData === true;
        this.billStatusMessage = data.mensagem || '';
        this.logSimulationInputs();
    }

    logSimulationInputs() {
        const simulationInputs = {
            modoEntrada: this.selectedEnergyInputMode,
            faixaCusto: this.selectedRange,
            valorMedioSelecionado: this.manualMonthlyCost,
            valorMedioDaFaixa: this.monthlyCostFromRange(this.selectedRange),
            custoTotalUtilizado: this.energyData?.contaEstimada,
            monthlyCostRetornado: this.energyData?.monthlyCost,
            descontoPercentual: this.energyData?.descontoPercent,
            tarifaKwhComImpostos: this.energyData?.tarifaKwhComImpostos,
            iluminacaoPublica: this.energyData?.iluminacaoPublica,
            tipoLigacao: this.selectedLigacao,
            disponibilidadeKwh: this.energyData?.disponibilidadeKwh,
            consumoTotalKwh: this.energyData?.consumoTotalKwh,
            compensavelKwh: this.energyData?.kwhContratado,
            deducoes: this.energyData?.deducoes,
            custoTotalComDeducoes: this.energyData?.custoTotalComDeducoes,
            tarifaComDesconto: this.energyData?.tarifaComDesconto,
            boletoDistribuidora: this.energyData?.boletoDistribuidora,
            boletoGeradorParceiro: this.energyData?.boletoGeradorParceiro,
            totalDoisBoletos: this.energyData?.totalDoisBoletos,
            economiaMensal: this.energyData?.economiaMensal,
            economiaAnual: this.energyData?.economiaAnual
        };

        // Mantido temporariamente para validar os insumos da simulação do totem.
        // eslint-disable-next-line no-console
        console.log('[TotemOportunidadesFluxo] Entradas da simulação:', JSON.stringify(simulationInputs, null, 2));
    }

    monthlyCostFromRange(value) {
        if (!value) {
            return null;
        }

        const selected = ENERGY_RANGES.find((range) => range.value === value || range.label === value);
        if (selected) {
            return selected.amount;
        }

        const normalized = String(value).trim().toLowerCase();
        if (
            normalized.includes('1.000') ||
            normalized.includes('1000') ||
            normalized.includes('acima')
        ) {
            return 850;
        }
        if (normalized.includes('500') && normalized.includes('700')) {
            return 600;
        }
        if (normalized.includes('200') && (normalized.includes('500') || normalized.includes('400'))) {
            return 350;
        }
        if (
            normalized.includes('200') &&
            (normalized.includes('menor') || normalized.includes('até') || normalized.includes('ate'))
        ) {
            return 200;
        }
        return null;
    }

    /* ── Step 2 selections ──────────────────────────────────── */
    selectSolar(event) {
        this.hasSolar = event.currentTarget.dataset.value === 'sim';
    }

    selectLigacao(event) {
        this.selectedLigacao = event.currentTarget.dataset.value;
    }

    selectEnergyInputMode(event) {
        this.selectedEnergyInputMode = event.currentTarget.dataset.value;
        this.errorMessage = '';
        this.billStatusMessage = '';
        if (this.isAverageMode) {
            this.stopCamera();
        } else {
            this.manualEnergySaved = false;
        }
    }

    selectEnergyRange(event) {
        const value = event.currentTarget.dataset.value;
        const selected = ENERGY_RANGES.find((range) => range.value === value);
        this.selectedRange = value;
        this.manualMonthlyCost = selected?.amount || null;
        this.manualEnergySaved = false;
    }

    triggerBillFileInput() {
        const input = this.template.querySelector('input[data-id="billFileInput"]');
        if (input) {
            input.click();
        }
    }

    async startCamera() {
        this.resetBillDocument();
        this.billCaptureMode = 'CAMERA';
        this.errorMessage = '';
        this.billStatusMessage = '';

        if (!navigator.mediaDevices?.getUserMedia) {
            this.errorMessage = 'Não foi possível acessar a câmera deste dispositivo.';
            return;
        }

        try {
            this.cameraStream = await navigator.mediaDevices.getUserMedia({
                audio: false,
                video: { facingMode: { ideal: 'environment' } }
            });
            this.isCameraOpen = true;
            await Promise.resolve();
            this.attachCameraStream();
        } catch (error) {
            this.stopCamera();
            this.errorMessage = 'Não foi possível acessar a câmera. Verifique a permissão e tente novamente.';
        }
    }

    attachCameraStream() {
        const video = this.template.querySelector('video[data-id="billCamera"]');
        if (video && this.cameraStream) {
            video.srcObject = this.cameraStream;
        }
    }

    capturePhoto() {
        const video = this.template.querySelector('video[data-id="billCamera"]');
        if (!video) {
            this.errorMessage = 'Não foi possível capturar a imagem. Tente novamente.';
            return;
        }

        const canvas = document.createElement('canvas');
        canvas.width = video.videoWidth || 1280;
        canvas.height = video.videoHeight || 720;
        const context = canvas.getContext('2d');
        context.drawImage(video, 0, 0, canvas.width, canvas.height);
        const dataUrl = canvas.toDataURL('image/jpeg', 0.9);

        this.billFileName = `conta-energia-${Date.now()}.jpg`;
        this.billFileType = 'image/jpeg';
        this.billFileBase64 = dataUrl.split(',')[1];
        this.billPreviewUrl = dataUrl;
        this.billCaptureMode = 'CAMERA';
        this.billRecognitionValid = false;
        this.billStatusMessage = 'Foto pronta para análise.';
        this.stopCamera();
    }

    retakePhoto() {
        this.resetBillDocument();
        this.startCamera();
    }

    stopCamera() {
        if (this.cameraStream) {
            this.cameraStream.getTracks().forEach((track) => track.stop());
            this.cameraStream = null;
        }
        this.isCameraOpen = false;
    }

    handleBillFileChange(event) {
        const file = event.target.files?.[0];
        if (!file) {
            return;
        }

        this.stopCamera();
        this.resetBillDocument();
        this.billCaptureMode = 'FILE';
        this.errorMessage = '';
        this.billStatusMessage = '';

        const validationMessage = this.validateSelectedFile(file);
        if (validationMessage) {
            this.errorMessage = validationMessage;
            event.target.value = '';
            return;
        }

        const reader = new FileReader();
        reader.onload = () => {
            const dataUrl = reader.result || '';
            this.billFileName = file.name;
            this.billFileType = file.type;
            this.billFileBase64 = String(dataUrl).split(',')[1];
            this.billPreviewUrl = file.type?.startsWith('image/') ? dataUrl : '';
            this.billRecognitionValid = false;
            this.billStatusMessage = 'Arquivo pronto para análise.';
        };
        reader.onerror = () => {
            this.errorMessage = 'Não foi possível carregar o arquivo. Tente novamente.';
        };
        reader.readAsDataURL(file);
    }

    validateSelectedFile(file) {
        const extension = this.fileExtension(file.name);
        if (!ACCEPTED_BILL_EXTENSIONS.includes(extension)) {
            return 'Formato não suportado. Envie PDF, JPG, JPEG ou PNG.';
        }

        const maxSize = (Number(this.maxBillFileSizeMb) || 4) * 1024 * 1024;
        if (file.size > maxSize) {
            return 'Arquivo acima do tamanho permitido para envio.';
        }
        return '';
    }

    resetBillDocument() {
        this.billFileName = '';
        this.billFileBase64 = '';
        this.billFileType = '';
        this.billPreviewUrl = '';
        this.billRecognitionValid = false;
    }

    async advanceToStep3() {
        const requiredFields = [
            { label: 'se você possui energia solar', value: this.hasSolar !== null },
            { label: 'o tipo de ligação elétrica', value: this.selectedLigacao }
        ];

        if (this.isAverageMode) {
            requiredFields.push({ label: 'o valor médio da conta', value: this.selectedRange && this.manualMonthlyCost });
        } else {
            requiredFields.push({
                label: 'a foto ou o arquivo da conta de energia',
                value: this.billRecognitionValid || this.hasBillFile
            });
        }

        const missingFields = this.getMissingFields(requiredFields);

        if (missingFields.length) {
            this.errorMessage = `Para continuar, selecione ${this.formatFieldList(missingFields)}.`;
            return;
        }

        this.errorMessage = '';
        this.billStatusMessage = '';

        if (this.isAverageMode || (this.billRecognitionValid && !this.hasBillFile)) {
            await this.saveEnergyChoicesAndGoToStep3();
            return;
        }

        await this.processBillAndGoToStep3();
    }

    async saveEnergyChoicesAndGoToStep3() {
        this.isProcessingBill = true;
        const opportunityId = this.resolvedOpportunityId;
        const leadId = this.resolvedLeadId;
        try {
            const result = await salvarEscolhasContaEnergia({
                opportunityId,
                leadId,
                hasSolar: this.hasSolar,
                tipoLigacao: this.selectedLigacao,
                monthlyCost: this.isAverageMode ? this.manualMonthlyCost : null,
                faixaCusto: this.isAverageMode ? this.selectedRange : null
            });
            this.applyEnergyData(result || {});
            if (result?.status && result.status !== 'OK') {
                this.errorMessage = result.mensagem || 'Não foi possível salvar os dados da conta. Tente novamente.';
                return;
            }
            this.manualEnergySaved = this.isAverageMode && result?.status === 'OK';
            this.currentStep = 3;
        } catch (error) {
            console.error('[TotemOportunidadesFluxo] Erro ao salvar dados da conta:', error);
            this.errorMessage = 'Não foi possível salvar os dados da conta. Tente novamente.';
        } finally {
            this.isProcessingBill = false;
        }
    }

    async processBillAndGoToStep3() {
        this.isProcessingBill = true;
        this.billStatusMessage = 'Analisando a conta de energia...';
        const opportunityId = this.resolvedOpportunityId;
        const leadId = this.resolvedLeadId;
        try {
            const result = await processarContaEnergia({
                opportunityId,
                leadId,
                fileName: this.billFileName,
                base64Data: this.billFileBase64,
                contentType: this.billFileType,
                hasSolar: this.hasSolar,
                tipoLigacao: this.selectedLigacao,
                maxFileSizeMb: Number(this.maxBillFileSizeMb) || 4
            });

            this.applyEnergyData(result || {});
            this.billStatusMessage = result?.mensagem || '';

            if (result?.status === 'OK' && result?.hasRequiredEnergyData) {
                this.clearBillFileSelection();
                this.currentStep = 3;
                return;
            }

            this.errorMessage = result?.mensagem || 'Não foi possível analisar a conta neste momento. Tente novamente em alguns instantes.';
        } catch (error) {
            this.errorMessage = 'Não foi possível analisar a conta neste momento. Tente novamente em alguns instantes.';
        } finally {
            this.isProcessingBill = false;
        }
    }

    clearBillFileSelection() {
        this.billFileName = '';
        this.billFileBase64 = '';
        this.billFileType = '';
        this.billPreviewUrl = '';
    }

    /* ── Generic navigation ─────────────────────────────────── */
    goToStep2() {
        this.loadEnergyData();
        this.currentStep = 2;
    }
    goToStep3() { this.currentStep = 3; }
    goToStep4() {
        if (!this.hasSimulationData) {
            this.errorMessage = 'Não foi possível gerar uma simulação válida com os dados informados.';
            return;
        }
        this.errorMessage = '';
        this.currentStep = 4;
    }

    goToPreviousStep() {
        this.errorMessage = '';
        this.currentStep = Math.max(1, this.currentStep - 1);
    }

    goToNextStep() {
        this.errorMessage = '';
        this.currentStep = Math.min(5, this.currentStep + 1);
    }

    /* ── Step 4 submit ──────────────────────────────────────── */
    async handleConfirmar() {
        const liveFormData = this.getLiveFormData();
        const resolvedLeadId = this.resolvedLeadId;
        const resolvedOpportunityId = this.resolvedOpportunityId;
        this.formData = liveFormData;

        const missingFields = this.getMissingFields([
            { label: 'nome completo', value: liveFormData.nomeCompleto.trim() },
            { label: 'CPF', value: liveFormData.cpf.trim() },
            { label: 'data de nascimento', value: liveFormData.dataNasc.trim() },
            { label: 'WhatsApp', value: liveFormData.whatsapp.trim() },
            { label: 'e-mail', value: liveFormData.email.trim() },
            { label: 'a confirmação de energia solar', value: this.hasSolar !== null },
            { label: 'o tipo de ligação elétrica', value: this.selectedLigacao },
            { label: 'uma conta ou valor médio validado', value: this.hasValidEnergyForReview },
            { label: 'uma oportunidade válida', value: resolvedOpportunityId },
            { label: 'aceitar os Termos e Condições', value: liveFormData.aceitaTermos },
            { label: 'aceitar os Termos de privacidade e LGPD', value: liveFormData.aceitaPrivacidade },
            { label: 'aceitar o Contrato', value: liveFormData.aceitaContrato },
            { label: 'aceitar a Procuração', value: !this.shouldShowProcuracaoConsent || liveFormData.aceitaProcuracao },
            { label: 'autorizar o contato via WhatsApp', value: !this.shouldShowContactConsent || liveFormData.aceitaContato },
            { label: 'concluir a assinatura eletrônica', value: this.clicksignRequirementSatisfied }
        ]);

        if (missingFields.length) {
            this.errorMessage = `Para concluir, preencha ${this.formatFieldList(missingFields)}.`;
            return;
        }
        this.errorMessage = '';
        this.isSubmitting = true;

        try {
            console.info('[TotemOportunidadesFluxo] Aceites enviados:', {
                leadId: resolvedLeadId,
                opportunityId: resolvedOpportunityId,
                aceitaTermos: liveFormData.aceitaTermos,
                aceitaPrivacidade: liveFormData.aceitaPrivacidade,
                aceitaContrato: liveFormData.aceitaContrato,
                aceitaProcuracao: liveFormData.aceitaProcuracao,
                aceitaContato: liveFormData.aceitaContato
            });

            const result = await processarAdesaoPorValor({
                leadId: resolvedLeadId,
                opportunityId: resolvedOpportunityId,
                allowCreateNew: this.allowCreateNew,
                searchType: this.searchData.type,
                searchValue: this.searchData.value,
                nomeCompleto: liveFormData.nomeCompleto,
                cpf: liveFormData.cpf,
                dataNasc: liveFormData.dataNasc,
                email: liveFormData.email,
                whatsapp: liveFormData.whatsapp,
                energyRange: this.selectedRange,
                hasSolar: this.hasSolar,
                tipoLigacao: this.selectedLigacao,
                aceitaTermos: liveFormData.aceitaTermos,
                aceitaPoliticaPrivacidade: liveFormData.aceitaPrivacidade,
                aceitaContato: liveFormData.aceitaContato,
                monthlyCost: this.sim.conta || this.manualMonthlyCost || null,
                leadSource: this.leadSource,
                leadOrigin: this.leadOrigin,
                formWeb: this.formWeb,
                partnerCode: this.partnerCode,
                campaignCode: this.campaignCode,
                pageIdentifier: this.pageIdentifier
            });

            this.opportunityCode = result.codigoUnico || '';
            this.currentStep = 5;
        } catch (error) {
            this.errorMessage =
                error?.body?.message || error?.message || 'Não foi possível processar a adesão.';
        } finally {
            this.isSubmitting = false;
        }
    }

    firstNumber(...values) {
        for (const value of values) {
            const numberValue = this.numberOrNull(value);
            if (numberValue !== null) {
                return numberValue;
            }
        }
        return null;
    }

    numberOrNull(value) {
        const numberValue = Number(value);
        if (Number.isNaN(numberValue) || !Number.isFinite(numberValue) || numberValue < 0) {
            return null;
        }
        return numberValue;
    }

    formatDisplayNumber(value) {
        const numberValue = Number(value);
        if (Number.isNaN(numberValue) || !Number.isFinite(numberValue)) {
            return 'Não calculado';
        }
        return numberValue.toLocaleString('pt-BR', {
            minimumFractionDigits: numberValue % 1 === 0 ? 0 : 2,
            maximumFractionDigits: 2
        });
    }

    formatCurrency(value, suffix = '') {
        const numberValue = this.numberOrNull(value);
        if (numberValue === null) {
            return 'Não calculado';
        }
        return `R$ ${this.formatDisplayNumber(numberValue)}${suffix}`;
    }

    formatPercent(value) {
        const numberValue = this.numberOrNull(value);
        if (numberValue === null) {
            return 'Não calculado';
        }
        return `até ${this.formatDisplayNumber(numberValue)}%`;
    }

    fileExtension(fileName) {
        if (!fileName || !fileName.includes('.')) {
            return '';
        }
        return fileName.split('.').pop().toLowerCase();
    }

    restart() {
        this.stopCamera();
        this.currentStep = 1;
        this.lookupState = LOOKUP_STATE.SEARCH;
        this.lookupMessage = '';
        this.lookupMatches = [];
        this.searchData = {
            type: 'CODIGO',
            value: '',
            cpf: ''
        };
        this.hasSolar = null;
        this.selectedLigacao = null;
        this.selectedEnergyInputMode = ENERGY_INPUT_MODE.AVERAGE;
        this.selectedRange = null;
        this.manualMonthlyCost = null;
        this.manualEnergySaved = false;
        this.energyData = null;
        this.billCaptureMode = null;
        this.billFileName = '';
        this.billFileBase64 = '';
        this.billFileType = '';
        this.billPreviewUrl = '';
        this.isCameraOpen = false;
        this.isProcessingBill = false;
        this.billRecognitionValid = false;
        this.billStatusMessage = '';
        this.errorMessage = '';
        this.isSearching = false;
        this.isConfirmingCustomer = false;
        this.isSubmitting = false;
        this.opportunityCode = '';
        this.clicksignStatus = 'DISABLED';
        this.clicksignDocumentId = '';
        this.clicksignSignatureKey = '';
        this.isClicksignLoading = false;
        this.localizedLeadId = null;
        this.localizedOpportunityId = null;
        this.validatedByCode = false;
        this.allowCreateNew = false;
        this.formData = {
            nomeCompleto: '',
            cpf: '',
            dataNasc: '',
            whatsapp: '',
            email: '',
            aceitaTermos: false,
            aceitaPrivacidade: false,
            aceitaContrato: false,
            aceitaProcuracao: false,
            aceitaContato: false
        };
    }
}