import { LightningElement,track, api, wire} from 'lwc';
import { FlexCardMixin } from 'omnistudio/flexCardMixin';
import { getDataHandler } from 'omnistudio/utility'; 
import getFeatureManager from '@salesforce/apex/CKBR_CTL_ProductShowCase.getFeatureManager';
import { ShowToastEvent } from 'lightning/platformShowToastEvent'; 
const options = {}; 
export default class TelaPocRendaAlta extends FlexCardMixin(LightningElement) {
    @track datalist = []; 
    @track disabledRows = false;
    @track isShowDetalhes = false;
    @track isShowAplicar = false; 
    @track spinnerTable = true;
    @track isMobileOrTablet = false;
    @track isdatalist = false;
    @track searchterm = '';
    @track delayTimeout;
    @track isModalDisabledFunctionality = false;
    @track investmentSelected = ''; 
    @track originalDataList = [];
    @track vitrineAPIList = [];
    @track isSpinnerShowCase; 
    @api featureApiName = 'CKBR_LWC_ProductShowCase';
    @api recordId; 
    isFeatureActive;
    featureDisabledMessage;
    disabledSinv;
    @wire(getFeatureManager, {
        featureApiName: '$featureApiName'
    }) wiredFeatureManager({
        error,
        data
    }) {
        if (data) {
            this.isFeatureActive = data.isActive;
            this.featureDisabledMessage = data.featureDisabledMessage;
            this.disabledSinv = data.featureName;
            console.log('data.isActive >>> test' + data.isActive);
            if (data.isActive == false) {
                this.isModalDisabledFunctionality = true;
            } else {
                this.isModalDisabledFunctionality = false;
            }
        } else if (error) {
            this.isFeatureActive = false;
            this.featureDisabledMessage = 'Erro ao carregar a funcionalidade.';
        }
    }
    connectedCallback() {
        console.log('recordId >>> test' + this.recordId);
        this.spinnerTable = true;     
        this.getOmniStudioVIP();   
        this.checkDeviceType();
        this._resizeHandler = this.checkDeviceType.bind(this);  
        window.addEventListener('resize', this._resizeHandler);  

        //this.getDataVitrine();  
    }
    disconnectedCallback() {
        window.removeEventListener('resize', this._resizeHandler);
    }
    checkDeviceType() {
        this.isMobileOrTablet = window.innerWidth <= 1024;
    }
 

    @track showSortModal = false;
    @track sortBy = '';
    @track isMenuOpen = false;
    toggleMenu() {
        this.isMenuOpen = !this.isMenuOpen;
    }
    handleSortByClass() {
        this.sortBy = 'classeAtivo';
        this.sortData();
        this.handleCloseSortModal();
    }
    handleSortByName() {
        this.sortBy = 'nomeAZ';
        this.sortData();
        this.handleCloseSortModal();
    }
    handleSortByMinApplication() {
        this.sortBy = 'aplicacaoMinima';
        this.sortData();
        this.handleCloseSortModal();
    }
    handleSortByRisk() {
        this.sortBy = 'menorRisco';
        this.sortData();
        this.handleCloseSortModal(); 
    }
    handleApplySort() {
        this.sortData();
        this.handleCloseSortModal();
    }
    handleRemoveSort() {
        this.sortBy = '';
        this.datalist = [...this.originalDataList];
        this.handleCloseSortModal();
    }
    handleCloseSortModal() {
        this.isMenuOpen = false; 
    }

    sortData() {
        switch (this.sortBy) {
            case 'classeAtivo':
                this.datalist.sort((a, b) => a.classeAtivoDescricao.localeCompare(b.classeAtivoDescricao));
                break;
            case 'nomeAZ':
                this.datalist.sort((a, b) => a.nome.localeCompare(b.nome));
                break;
            case 'aplicacaoMinima':
                this.datalist.sort((a, b) => {
                    const minAppA = parseFloat(a.aplicacaoMinima.replace('R$ ', '').replace('.', '').replace(',', '.'));
                    const minAppB = parseFloat(b.aplicacaoMinima.replace('R$ ', '').replace('.', '').replace(',', '.'));
                    return minAppA - minAppB;
                });
                break;
            case 'menorRisco':
                this.datalist.sort((a, b) => a.riskLevel - b.riskLevel);
                break;
            default:
                break;
        }
    }

     
    handleSearchChange(event) {
        this.searchterm = event.target.value;
        this.debounceFilter();
    }
    debounceFilter() {
        clearTimeout(this.delayTimeout);
        this.delayTimeout = setTimeout(() => {
            this.filterData();
        }, 300);
    }
    filterData() {
        if (this.searchterm) {
            const searchKeywords = this.searchterm.toLowerCase().split(/\s+/);
            this.datalist = this.originalDataList.filter(record => {
                return searchKeywords.every(keyword => {
                    const nomeMatch = record.nome && record.nome.toLowerCase().includes(keyword);
                    const tipoMatch = record.tipo && record.tipo.toLowerCase().includes(keyword);
                    const aplicacaoMinimaMatch = record.aplicacaoMinima && record.aplicacaoMinima.toLowerCase().includes(keyword);
                    const horarioMovimentacaoMatch = record.horarioMovimentacao && record.horarioMovimentacao.toLowerCase().includes(keyword);
                    return nomeMatch || tipoMatch || aplicacaoMinimaMatch || horarioMovimentacaoMatch;
                });
            });
        } else {
            this.datalist = [...this.originalDataList];
        }
    }
    getOmniStudioVIP() { 
        let optionsMap = {    
            "aRecordId" : this.recordId 
        } 
        let vipRes = JSON.stringify({
            type: 'integrationprocedure',
            value: {  
                ipMethod: 'CKBR_VitrineProdutoRendaFixa',  
                inputMap: JSON.stringify(optionsMap), 
            }, 
        }); 
        getDataHandler(vipRes).then((data) => { 
            let responseIP = JSON.parse(data); 
            console.log('responseIP' + JSON.stringify(responseIP));  
            if (responseIP.IPResult?.faturas?.length >= 5) {
                console.log('entrou no if');  
                this.datalist = responseIP.IPResult.faturas.map((fatura, index) => ({
                    id: index++,  
                    nome: fatura?.nome || 'N/A', 
                    tipo: fatura?.categoria?.tipo || 'N/A',
                    aplicacaoMinima: 'R$ ' + fatura.movimentacao?.aplicacaoMinima || 'N/A',
                    horarioMovimentacao: fatura.movimentacao?.horarioAbertura + ' às ' + fatura?.movimentacao?.horarioFechamento || 'N/A',
                    classeAtivoCor: fatura?.classeAtivo?.cor || 'N/A',  
                    classeAtivoDescricao: fatura?.classeAtivo?.descricao || 'N/A',
                    riskLevel: fatura?.riskLevel || 1, 
                    circleStyle: this.getCircleStyle(fatura?.classeAtivo.cor),
                    riskBarStyle: this.getRiskBarStyle(fatura?.classeAtivo.cor),
                    riskDescription: this.getRiskDescription(fatura?.riskLevel),
                    financialAccountId : this.recordId, 
                })); 
            }
            this.originalDataList = [...this.datalist];
            this.spinnerTable = false;
            this.isdatalist = true;
            this.isFeatureActive = true;  
            this.vitrineAPIList =  responseIP.IPResult.faturas;  
            console.log('entrou no getHandler'); 
        }).catch((error) => {
            console.log('entrou no catch error');   
            this.showToastMessage('Erro', 'Erro no serviço da Integration Procedure de Renda Alta', 'error');
        });
    }
    getRiskBarStyle(color) {
        return `background-color: ${color};`;
    }
    getCircleStyle(color) { 
        return `background-color: ${color}; width: 15px; height: 15px; border-radius: 50%;`;
    }
 
    getRiskDescription(riskLevel) {
        switch (riskLevel) {
            case 1:
                return 'Muito baixo';
            case 2:
                return 'Baixo';
            case 3:
                return 'Médio';
            case 4:
                return 'Alto';
            case 5:
                return 'Muito alto';
            default:
                return 'Muito Baixo';
        }
    }
    handleRowActionDetalhes(event) {
        const targetDetalhes = event.currentTarget.dataset.id;
        this.investmentSelected = this.datalist.find(item => item.id === parseInt(targetDetalhes));
        this.isShowDetalhes = true;
    }
    handleRowActionAplicar(event) {
        const targetAplicar = event.currentTarget.dataset.id;
        if(this.investmentSelected?.id != parseInt(targetAplicar)){
            this.investmentSelected = this.datalist.find(item => item.id === parseInt(targetAplicar));
        }  
        
        if(!this.isShowAplicar){
            console.log('entrou no if'); 

            console.log('entrou no if');
            this.isShowAplicar = true; 
            console.log('entrou no if value');
        } 
        
    }
    hancleCloseEvent(event) {
        this.isShowDetalhes = event.detail.isShowDetalhes;
    }
    handleCloseDetalhesEvent(event) {
        this.isShowDetalhes = event.detail.isShowDetalhes;
        this.isShowAplicar = true;
    }
    handleCloseAplicarEvent(event) { 
        console.log('event.detail.isShowAplicar' + event.detail.isShowAplicar); 
        this.isShowAplicar = event.detail.isShowAplicar;
        console.log('this.isShowAplicar' + this.isShowAplicar); 
    }
    showToastMessage(titleMsg, messageMsg, variantMsg) {
        const evt = new ShowToastEvent({ 
            title: titleMsg,
            message: messageMsg,
            variant: variantMsg,
        });
        this.dispatchEvent(evt);
    }
}