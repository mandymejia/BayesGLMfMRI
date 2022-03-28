// Generated by using Rcpp::compileAttributes() -> do not edit by hand
// Generator token: 10BE3573-1514-4C36-9D1C-5A225CD40393

#include <RcppEigen.h>
#include <Rcpp.h>

using namespace Rcpp;

#ifdef RCPP_USE_GLOBAL_ROSTREAM
Rcpp::Rostream<true>&  Rcpp::Rcout = Rcpp::Rcpp_cout_get();
Rcpp::Rostream<false>& Rcpp::Rcerr = Rcpp::Rcpp_cerr_get();
#endif

// logDetQt
double logDetQt(double kappa2, const Rcpp::List& in_list, double n_sess);
RcppExport SEXP _BayesfMRI_logDetQt(SEXP kappa2SEXP, SEXP in_listSEXP, SEXP n_sessSEXP) {
BEGIN_RCPP
    Rcpp::RObject rcpp_result_gen;
    Rcpp::traits::input_parameter< double >::type kappa2(kappa2SEXP);
    Rcpp::traits::input_parameter< const Rcpp::List& >::type in_list(in_listSEXP);
    Rcpp::traits::input_parameter< double >::type n_sess(n_sessSEXP);
    rcpp_result_gen = Rcpp::wrap(logDetQt(kappa2, in_list, n_sess));
    return rcpp_result_gen;
END_RCPP
}
// initialKP
Eigen::VectorXd initialKP(Eigen::VectorXd theta, List spde, Eigen::VectorXd w, double n_sess, double tol, bool verbose);
RcppExport SEXP _BayesfMRI_initialKP(SEXP thetaSEXP, SEXP spdeSEXP, SEXP wSEXP, SEXP n_sessSEXP, SEXP tolSEXP, SEXP verboseSEXP) {
BEGIN_RCPP
    Rcpp::RObject rcpp_result_gen;
    Rcpp::traits::input_parameter< Eigen::VectorXd >::type theta(thetaSEXP);
    Rcpp::traits::input_parameter< List >::type spde(spdeSEXP);
    Rcpp::traits::input_parameter< Eigen::VectorXd >::type w(wSEXP);
    Rcpp::traits::input_parameter< double >::type n_sess(n_sessSEXP);
    Rcpp::traits::input_parameter< double >::type tol(tolSEXP);
    Rcpp::traits::input_parameter< bool >::type verbose(verboseSEXP);
    rcpp_result_gen = Rcpp::wrap(initialKP(theta, spde, w, n_sess, tol, verbose));
    return rcpp_result_gen;
END_RCPP
}
// findTheta
Rcpp::List findTheta(Eigen::VectorXd theta, List spde, Eigen::VectorXd y, Eigen::SparseMatrix<double> X, Eigen::SparseMatrix<double> QK, Eigen::SparseMatrix<double> Psi, Eigen::SparseMatrix<double> A, int Ns, double tol, bool verbose);
RcppExport SEXP _BayesfMRI_findTheta(SEXP thetaSEXP, SEXP spdeSEXP, SEXP ySEXP, SEXP XSEXP, SEXP QKSEXP, SEXP PsiSEXP, SEXP ASEXP, SEXP NsSEXP, SEXP tolSEXP, SEXP verboseSEXP) {
BEGIN_RCPP
    Rcpp::RObject rcpp_result_gen;
    Rcpp::traits::input_parameter< Eigen::VectorXd >::type theta(thetaSEXP);
    Rcpp::traits::input_parameter< List >::type spde(spdeSEXP);
    Rcpp::traits::input_parameter< Eigen::VectorXd >::type y(ySEXP);
    Rcpp::traits::input_parameter< Eigen::SparseMatrix<double> >::type X(XSEXP);
    Rcpp::traits::input_parameter< Eigen::SparseMatrix<double> >::type QK(QKSEXP);
    Rcpp::traits::input_parameter< Eigen::SparseMatrix<double> >::type Psi(PsiSEXP);
    Rcpp::traits::input_parameter< Eigen::SparseMatrix<double> >::type A(ASEXP);
    Rcpp::traits::input_parameter< int >::type Ns(NsSEXP);
    Rcpp::traits::input_parameter< double >::type tol(tolSEXP);
    Rcpp::traits::input_parameter< bool >::type verbose(verboseSEXP);
    rcpp_result_gen = Rcpp::wrap(findTheta(theta, spde, y, X, QK, Psi, A, Ns, tol, verbose));
    return rcpp_result_gen;
END_RCPP
}

static const R_CallMethodDef CallEntries[] = {
    {"_BayesfMRI_logDetQt", (DL_FUNC) &_BayesfMRI_logDetQt, 3},
    {"_BayesfMRI_initialKP", (DL_FUNC) &_BayesfMRI_initialKP, 6},
    {"_BayesfMRI_findTheta", (DL_FUNC) &_BayesfMRI_findTheta, 10},
    {NULL, NULL, 0}
};

RcppExport void R_init_BayesfMRI(DllInfo *dll) {
    R_registerRoutines(dll, NULL, CallEntries, NULL, NULL);
    R_useDynamicSymbols(dll, FALSE);
}
