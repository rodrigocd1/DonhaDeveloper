import { LightningElement } from "lwc";
import basePath from "@salesforce/community/basePath";
import obterLojaPadrao from "@salesforce/apex/PesquisasPortalController.obterLojaPadrao";

export default class PesquisasCorretorCheckinCard extends LightningElement {
  store;
  errorMessage;
  isLoading = true;

  connectedCallback() {
    this.loadDefaultStore();
  }

  async loadDefaultStore() {
    this.isLoading = true;
    this.errorMessage = undefined;
    try {
      this.store = await obterLojaPadrao();
    } catch (error) {
      this.errorMessage =
        error?.body?.message || "Não foi possível carregar a loja padrão.";
    } finally {
      this.isLoading = false;
    }
  }

  get checkinUrl() {
    if (!this.store) {
      return undefined;
    }
    const communityPath = (basePath || "").replace(/\/$/, "");
    return `${communityPath}/checkin-corretor?loja=${encodeURIComponent(
      this.store.codigo
    )}`;
  }

  get absoluteCheckinUrl() {
    return this.checkinUrl
      ? `${window.location.origin}${this.checkinUrl}`
      : undefined;
  }
}
