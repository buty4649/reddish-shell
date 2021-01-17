%{
#include <string.h>
#include <stdio.h>
#include "mruby.h"
#include "mruby/string.h"
#include "mruby/array.h"
#include "mruby/variable.h"

typedef struct parser_state {
    mrb_state* state;
    mrb_value  result;
    mrb_value  action;
    mrb_value  lexer;
} parser_state;

#define ACTION(p, n, c, ...)   mrb_funcall(p->state, p->action, n, c, __VA_ARGS__)
#define APPEND_REDIRECT(p, s, r)  ACTION(p, "on_append_redirect", 2, s, r)
#define COMMAND(p, e)             ACTION(p, "on_command", 1, e)
#define CONNECTOR(p, t, a, b)     ACTION(p, "on_connector", 3, mrb_symbol_value(mrb_intern_cstr(p->state, t)), a, b)
#define IF_STMT(p, s, c, ...)     ACTION(p, "on_if_stmt", (c+2), s, MRB_FALSE, __VA_ARGS__)
#define PIPELINE(p, a, b, r)      ACTION(p, "on_pipeline", 3, a, b, r)
#define REDIRECT(p, t, c, ...)    ACTION(p, "on_redirect", (c+1), mrb_symbol_value(mrb_intern_cstr(p->state, t)), __VA_ARGS__)
#define SIMPLELIST(p, c, a)       ACTION(p, "on_simple_list", 2, c, a)
#define UNLESS_STMT(p, s, c, ...) ACTION(p, "on_if_stmt", (c+2), s, MRB_TRUE, __VA_ARGS__)
#define WORD(p, w)                ACTION(p, "on_word", 1, w)

#define FIXNUM(i) mrb_fixnum_value(i)
#define MRB_TRUE  mrb_true_value()
#define MRB_FALSE mrb_false_value()
#define NIL       mrb_nil_value()

#define YYDEBUG 1

static int yylex(void* , parser_state*);
static void yyerror(parser_state*, const char*);
static int yyparse(parser_state*);
%}

%define api.value.type {mrb_value}
%define api.pure
%parse-param {parser_state* p}
%lex-param {parser_state* p}

%token WORD NUMBER MINUS NUMBER_MINUS
%token IF THEN ELSE ELIF ELSIF FI END UNLESS
%token AND AND_AND OR OR_OR OR_AND SEMICOLON
%token GT GT_GT AND_GT GT_AND LT LT_AND LT_GT
%start inputunit

%%

inputunit
: %empty
| simple_list { p->result = $1; }

simple_list
: connector { $$ = SIMPLELIST(p, $1, MRB_FALSE); }
| connector AND       { $$ = SIMPLELIST(p, $1, MRB_TRUE); }
| connector SEMICOLON { $$ = SIMPLELIST(p, $1, MRB_FALSE); }

connector
: connector AND_AND   pipeline { $$ = CONNECTOR(p, "and", $1, $3); }
| connector OR_OR     pipeline { $$ = CONNECTOR(p, "or",  $1, $3); }
| connector AND       pipeline { $$ = CONNECTOR(p, "async", $1, $3); }
| connector SEMICOLON pipeline { $$ = CONNECTOR(p, "semicolon", $1, $3); }
| pipeline

pipeline
: pipeline OR command     { $$ = PIPELINE(p, $1, $3, MRB_FALSE); }
| pipeline OR_AND command { $$ = PIPELINE(p, $1, $3, MRB_TRUE); }
| command

compound_list
: connector SEMICOLON

command
: simple_command { $$ = COMMAND(p, $1); }
| shell_command
| shell_command redirect_list { APPEND_REDIRECT(p, $1, $2); $$ = $1; }

shell_command
: if_statement
| unless_statement

if_statement
: IF compound_list END                                      { $$ = IF_STMT(p, $2, 0, NULL); }
| IF compound_list ELSE compound_list END                   { $$ = IF_STMT(p, $2, 2, NIL, $4); }
| IF compound_list elsif_clause END                         { $$ = IF_STMT(p, $2, 2, NIL, $3); }
| IF compound_list THEN compound_list FI                    { $$ = IF_STMT(p, $2, 1, $4); }
| IF compound_list THEN compound_list END                   { $$ = IF_STMT(p, $2, 1, $4); }
| IF compound_list THEN compound_list ELSE compound_list FI { $$ = IF_STMT(p, $2, 2, $4, $6); }
| IF compound_list THEN compound_list ELSE compound_list END{ $$ = IF_STMT(p, $2, 2, $4, $6); }
| IF compound_list THEN compound_list elif_clause FI        { $$ = IF_STMT(p, $2, 2, $4, $5); }
| IF compound_list THEN compound_list elif_clause END       { $$ = IF_STMT(p, $2, 2, $4, $5); }
| IF compound_list THEN compound_list elsif_clause FI       { $$ = IF_STMT(p, $2, 2, $4, $5); }
| IF compound_list THEN compound_list elsif_clause END      { $$ = IF_STMT(p, $2, 2, $4, $5); }

elif_clause
: ELIF compound_list THEN compound_list                    { $$ = IF_STMT(p, $2, 1, $4); }
| ELIF compound_list THEN compound_list ELSE compound_list { $$ = IF_STMT(p, $2, 2, $4, $6); }
| ELIF compound_list THEN compound_list elif_clause        { $$ = IF_STMT(p, $2, 2, $4, $5); }
| ELIF compound_list THEN compound_list elsif_clause       { $$ = IF_STMT(p, $2, 2, $4, $5); }

elsif_clause
: ELSIF compound_list                                       { $$ = IF_STMT(p, $2, 0, NULL); }
| ELSIF compound_list ELSE compound_list                    { $$ = IF_STMT(p, $2, 2, NIL, $4); }
| ELSIF compound_list THEN compound_list                    { $$ = IF_STMT(p, $2, 1, $4); }
| ELSIF compound_list THEN compound_list ELSE compound_list { $$ = IF_STMT(p, $2, 2, $4, $6); }
| ELSIF compound_list THEN compound_list elif_clause        { $$ = IF_STMT(p, $2, 2, $4, $5); }
| ELSIF compound_list THEN compound_list elsif_clause       { $$ = IF_STMT(p, $2, 2, $4, $5); }

unless_statement
: UNLESS compound_list THEN compound_list END                   { $$ = UNLESS_STMT(p, $2, 1, $4); }
| UNLESS compound_list THEN compound_list ELSE compound_list END{ $$ = UNLESS_STMT(p, $2, 2, $4, $6); }

simple_command
: simple_command_element { $$ = mrb_ary_new_from_values(p->state, 1, &$1); }
| simple_command simple_command_element { mrb_ary_push(p->state, $1, $2); $$ = $1; }

simple_command_element
: WORD { $$ = WORD(p, $1); }
| redirect

redirect_list
: redirect
| redirect_list redirect { mrb_ary_concat(p->state, $1, $2); $$ = $1; }

redirect
/* <    */: LT WORD                    { $$ = REDIRECT(p, "read",     2, FIXNUM(0), $2); }
/* n<   */| NUMBER LT WORD             { $$ = REDIRECT(p, "read",     2, $1, $3); }
/* <&-  */| LT_AND MINUS               { $$ = REDIRECT(p, "close",    1, FIXNUM(0)); }
/* <&n  */| LT_AND NUMBER              { $$ = REDIRECT(p, "copyread", 2, FIXNUM(0), $2); }
/* <&n- */| LT_AND NUMBER MINUS        { $$ = REDIRECT(p, "copyreadclose", 2, FIXNUM(0), $2); }
/* n<&- */| NUMBER LT_AND MINUS        { $$ = REDIRECT(p, "close",    1, $1); }
/* n<&n */| NUMBER LT_AND NUMBER       { $$ = REDIRECT(p, "copyread", 2, $1, $3); }
/* n<&n-*/| NUMBER LT_AND NUMBER MINUS { $$ = REDIRECT(p, "copyreadclose", 2, $1, $3); }
/* >    */| GT WORD                    { $$ = REDIRECT(p, "write",     2, FIXNUM(1), $2); }
/* n>   */| NUMBER GT WORD             { $$ = REDIRECT(p, "write",     2, $1, $3); }
/* >&-  */| GT_AND MINUS               { $$ = REDIRECT(p, "close",     1, FIXNUM(1)); }
/* >&n  */| GT_AND NUMBER              { $$ = REDIRECT(p, "copywrite", 2, FIXNUM(1), $2); }
/* >&n- */| GT_AND NUMBER MINUS        { $$ = REDIRECT(p, "copywriteclose", 2, FIXNUM(1), $2); }
/* n>&- */| NUMBER GT_AND MINUS        { $$ = REDIRECT(p, "close",     1, $1); }
/* n>&n */| NUMBER GT_AND NUMBER       { $$ = REDIRECT(p, "copywrite", 2, $1, $3); }
/* n>&n-*/| NUMBER GT_AND NUMBER MINUS { $$ = REDIRECT(p, "copywriteclose", 2, $1, $3); }
/* &>   */| AND_GT WORD                { $$ = REDIRECT(p, "copystdoutstderr", 3, FIXNUM(1), FIXNUM(2), $2); }
/* >&   */| GT_AND WORD                { $$ = REDIRECT(p, "copystdoutstderr", 3, FIXNUM(1), FIXNUM(2), $2); }
/* >>   */| GT_GT WORD                 { $$ = REDIRECT(p, "append", 2, FIXNUM(1), $2); }
/* n>>  */| NUMBER GT_GT WORD          { $$ = REDIRECT(p, "append", 2, $1, $3); }
/* <>   */| LT_GT WORD                 { $$ = REDIRECT(p, "readwrite", 2, FIXNUM(0), $2); }
/* n<>  */| NUMBER LT_GT WORD          { $$ = REDIRECT(p, "readwrite", 2, $1, $3); }

%%
static const struct token_type {
    const char *name;
    int type;
} token_types[] = {
    {"&",  AND},
    {"&&", AND_AND},
    {"&>", AND_GT},
    {">",  GT},
    {">&", GT_AND},
    {">>", GT_GT},
    {"<",  LT},
    {"<&", LT_AND},
    {"<>", LT_GT},
    {"-",  MINUS},
    {"|",  OR},
    {"|&", OR_AND},
    {"||", OR_OR},
    {";",  SEMICOLON},
    {"eof", YYEOF},
    {"number", NUMBER},
    {"word", WORD},
    {"if", IF},
    {"then", THEN},
    {"else", ELSE},
    {"elif", ELIF},
    {"elsif", ELSIF},
    {"fi", FI},
    {"end", END},
    {"unless", UNLESS},
    {NULL, 0}
};

int sym2tt(const char *sym) {
    const struct token_type *tt;
    for (tt = token_types; tt->name; tt++) {
        if (strcmp(tt->name, sym) == 0) {
            return tt->type;
        }
    }
    return 0;
}

int yylex(void* lval, parser_state* p) {
    mrb_value token, token_type;
    int type;

    token = mrb_funcall(p->state, p->lexer, "get_token", 0);
    token_type = mrb_funcall(p->state, token, "type", 0);
    type = sym2tt(mrb_sym2name(p->state, mrb_symbol(token_type)));
    *((YYSTYPE*)lval) = mrb_funcall(p->state, token, "data", 0);

    return type;
}

void yyerror(parser_state* p, const char* s){
    mrb_value str = mrb_str_new_cstr(p->state, s);
    mrb_value state = mrb_funcall(p->state, p->lexer, "state", 0);
    mrb_funcall(p->state, p->action, "on_error", 2, str, state);
}


mrb_value mrb_reddish_parser_parse(mrb_state *mrb, mrb_value self) {
    mrb_value line, ifs, argv[2];
    mrb_value action, lexer;
    struct RClass *action_class;
    struct RClass *lexer_class;
    parser_state pstate;

    mrb_get_args(mrb, "SS!", &line, &ifs);

    action_class = mrb_class_get_under(mrb, mrb_module_get(mrb, "ReddishParser"), "Action");
    action = mrb_obj_new(mrb, action_class, 0, NULL);

    lexer_class = mrb_class_get_under(mrb, mrb_module_get(mrb, "ReddishParser"), "Lexer");
    argv[0] = line;
    argv[1] = ifs;
    lexer = mrb_obj_new(mrb, lexer_class, 2, argv);

    pstate.state = mrb;
    pstate.result = mrb_nil_value();
    pstate.action = action;
    pstate.lexer = lexer;

    yyparse(&pstate);

    if (mrb_nil_p(pstate.result)) {
        return mrb_nil_value();
    }

    return pstate.result;
}

mrb_value mrb_reddish_parser_debug(mrb_state *mrb, mrb_value self) {
    mrb_bool flag;
    mrb_get_args(mrb, "b", &flag);
    yydebug = flag;
    return mrb_bool_value(flag);
}
