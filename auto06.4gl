
DATABASE life

GLOBALS	"../def/pcinface.4gl"
GLOBALS	"../def/lf.4gl"
GLOBALS	"../def/log.4gl"
GLOBALS	"../def/bill.4gl"
GLOBALS	"../def/pmra.4gl"
GLOBALS	"../def/common.4gl"
GLOBALS	"../def/pswcmx.4gl"
GLOBALS	"../def/psdgdiv.4gl"
GLOBALS	"../def/disburst.4gl"
GLOBALS	"../def/ppinface.4gl"
GLOBALS	"../def/mpinface.4gl"
GLOBALS	"../def/vlinface.4gl"


MAIN

DEFINE	f_rcode			SMALLINT
DEFINE	f_add_month		SMALLINT
DEFINE	f_notice_day		SMALLINT
DEFINE	f_cal_date		CHAR(9)
DEFINE	f_counter		INTEGER
DEFINE	f_tot_cnt		INTEGER
DEFINE	f_compare_day		INTEGER
DEFINE  f_message               CHAR(78)
DEFINE	f_time		datetime hour to fraction
DEFINE  f_entry_class           CHAR(10)
--  LOCK	MODE
SET	LOCK MODE	TO WAIT

--  DEFER INTERRUPT
WHENEVER	ERROR	CONTINUE


--  added by kahn, 980615 because of standard
CALL	jobControl()	-- for begin


-------------------------------------------------------------------
--	◎ 基本輸入檢查
-------------------------------------------------------------------
LET	g_automatic_date = ARG_VAL(1)
LET     g_entry_ind      = ARG_VAL(2)    --分組指示
LET	g_bill_stat_ym   = ARG_VAL(3)
IF	(LENGTH(g_automatic_date CLIPPED) = 0)	THEN
        DISPLAY " 請輸入處理日期 !! "
        EXIT PROGRAM
END IF
CASE g_entry_ind
    WHEN 'X'
        LET f_entry_class = '[0147]' CLIPPED
        EXIT CASE
    WHEN 'Y'
        LET f_entry_class = '[258]' CLIPPED
        EXIT CASE
    WHEN 'Z'
        LET f_entry_class = '[369]' CLIPPED
        EXIT CASE
    OTHERWISE
        DISPLAY " 請輸入正確的組別 !! "
         EXIT PROGRAM
    --    LET f_entry_class = '[0123456789]' CLIPPED
END CASE

--display g_automatic_date

CALL	CheckDate(g_automatic_date)
	RETURNING f_rcode, g_automatic_date
IF	(f_rcode = FALSE)	THEN
        DISPLAY " 輸入日期有誤 !! "
        EXIT PROGRAM
END IF
LET	f_cal_date	= getdate(TODAY)
CALL chk_wkdt(g_automatic_date)
     RETURNING  f_rcode,f_message,g_holiday_ind
            IF  f_rcode = FALSE THEN
                DISPLAY "判斷假日有誤"
                LET g_holiday_ind = " "
            END IF

display 'holiday_ind=',g_holiday_ind

{==============================================
IF	addday(f_cal_date, 5) < g_automatic_date	THEN
        DISPLAY " 輸入日期有誤 !! 超過限定......"
        EXIT PROGRAM
END IF
==============================================}

let	f_time = current
display	'=trace=begin:  ', f_time, ' of ', g_automatic_date

-------------------------------------------------------------------
--	◎ 設定初值
-------------------------------------------------------------------
LET	g_program_id = 'psw000'
LET	f_rcode = 0
LET	f_counter = 0
LET	f_tot_cnt = 0

CALL	GetSeq("PC", "DAILY")
	RETURNING g_automatic_seq, f_message
IF	(f_message IS NOT NULL)	THEN	-- 表示有 warning message
	DISPLAY	'==err ', f_message CLIPPED
END IF
IF	(g_automatic_seq IS NULL)	THEN	-- 表示跟本 fetch 不到 seq#
	DISPLAY	'==err getseq make big trouble!!'
	EXIT	PROGRAM
END IF

-- 應 農曆年 20號提早出單日, 891220, kahn, 第一次改, 以後按此規則改
{
IF	g_automatic_date >= '090/01/01'
AND	g_automatic_date <= '090/01/19'	THEN
	LET	f_compare_day = 5 -- 提早到五號
ELSE
	LET	f_compare_day = 20
END	IF
}

--  將90/12, 91/01, 91/02 出單提早
IF	(g_automatic_date >= '090/11/01' AND	g_automatic_date <= '090/11/19')
OR	(g_automatic_date >= '090/12/01' AND	g_automatic_date <= '090/12/19')
OR	(g_automatic_date >= '091/01/01' AND	g_automatic_date <= '091/01/19')
THEN
	LET	f_compare_day = 9
ELSE
	LET	f_compare_day = 20
END	IF

IF	g_automatic_date[8,9] >= f_compare_day	THEN
	LET	f_add_month = 2
	CALL	InsScheduleBillDate( g_automatic_date)
ELSE
	LET	f_add_month = 1
END IF

LET	f_notice_day	= GetEtab("PC", "BILL-day") -- 15
LET	g_ren_notice	= AddDay(g_automatic_date, f_notice_day)
LET	f_cal_date	= g_automatic_date[1,7], "01"
LET	g_dead_line	= AddMonth(f_cal_date, f_add_month) -- 1 or 2 months
LET	g_dead_line	= SubtractDay(g_dead_line, 1) -- 本或下月底

-- 以下供m=7 使用
IF	g_automatic_date[8,9] >= 10	THEN
	LET	f_add_month = 2
ELSE
	LET	f_add_month = 1
END IF
LET	f_cal_date	= g_automatic_date[1,7], "01"
LET	g_ren_notice_1	= AddMonth(f_cal_date, f_add_month)
LET	g_ren_notice_1	= SubtractDay(g_ren_notice_1, 1) -- 本或下月底

-- 新增VUL使用, kahn, 9105
LET	f_notice_day	= GetEtab("PC", "vul_ren")	-- 25
LET	g_vul_ren		= AddDay(g_automatic_date, f_notice_day)

LET	g_ps_dept	= GetEtab("PP", "ps_dept")
IF	(LENGTH(g_bill_stat_ym   CLIPPED) = 0)	THEN
        LET g_bill_stat_ym = g_dead_line[1,6]
END IF


LET	g_tty = 'console'
SELECT	@USER	INTO	g_user
	FROM	SYSTABLES
	WHERE	@TABID = 1
SELECT	desc	INTO	g_nfo_day
	FROM	etab
	WHERE	code = 'PS'
	AND	e_type = 'nfo_day'
SELECT	desc	INTO	g_rem_day
	FROM	etab
	WHERE	code = 'PS'
	AND	e_type = 'remindr1'


--DELETE	FROM	pmra
--IF	SQLCA.SQLCODE <> 0 THEN
	--LET	g_rollback = TRUE
	--CALL	ShowMessage("pmra", 3, STATUS)
--	EXIT PROGRAM
--END IF


DISPLAY " 作業中 ... "

CALL	setinstype()	-- 因為半年前後停失效扣佣件
DECLARE	polf_ptr	CURSOR	WITH HOLD	FOR
	SELECT	*
		FROM	polf
        WHERE   next_activity_date > ' '
        AND next_activity_date <= g_automatic_date
        AND policy_no[1,1] = "6"
        AND policy_no[12,12] MATCHES f_entry_class
		ORDER BY policy_no

FOREACH	polf_ptr	INTO	g_polf.*
    IF  g_polf.next_activity_type = 'X' THEN
       DISPLAY "err(已下架) pls check n_type in polf. ",g_polf.policy_no
        ,' ',g_polf.next_activity_date,' ',g_polf.next_activity_type
	,'=',g_polf.po_sts_code,'=PTD=',g_polf.paid_to_date
        CONTINUE    FOREACH
    END IF
	LET	f_tot_cnt = f_tot_cnt + 1
	LET	f_rcode = atmain()
	IF	f_rcode = 0	THEN	-- denote correct
		LET	f_counter = f_counter + 1
	END IF

END FOREACH


let	f_time = current
display	'=trace=', f_time
DISPLAY " 完成保單自動化處理 ! : TIME=", f_time
DISPLAY " TOTAL Read == ", f_tot_cnt,"; TOTAL COUNT == ", f_counter

--  added by kahn, 980615 because of standard
CALL	jobControl()	-- for end

END MAIN

